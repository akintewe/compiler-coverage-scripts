import json, subprocess, sys

# demangled names we never want to see as gaps: the test suite runs rustc as a
# library so main() never fires, it shows up in every crate
NOISE_DEMANGLED = ['rustc_main::main', 'rustc_driver_impl::main']


def strip_generics(s):
    """Remove generic argument lists from a demangled name.

    `PlaceholderReplacer<InferCtxt, TyCtxt>::fold_const` -> `PlaceholderReplacer::fold_const`
    `fold_const::<T>` -> `fold_const`
    but keeps qualified-impl brackets: `<X as TypeFolder>::fold_const` stays.

    A `<` glued to an identifier (or `::<` turbofish) starts a generic list -> drop it.
    A `<` after a space / start of string is a qualified path -> keep it.
    """
    out = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == '<':
            prev = out[-1] if out else ''
            if prev and (prev.isalnum() or prev in '_:'):
                # skip the balanced <...> group
                depth = 1
                i += 1
                while i < n and depth > 0:
                    if s[i] == '<':
                        depth += 1
                    elif s[i] == '>' and s[i - 1] != '-':  # ignore `->` in fn types
                        depth -= 1
                    i += 1
                # drop a dangling turbofish `::`
                if len(out) >= 2 and out[-1] == ':' and out[-2] == ':':
                    out.pop(); out.pop()
                continue
        out.append(c)
        i += 1
    return ''.join(out)


def demangle_all(names):
    """Demangle a list of mangled names with rustfilt in one pass."""
    joined = '\n'.join(names)
    result = subprocess.run(['rustfilt'], input=joined, capture_output=True, text=True)
    demangled = result.stdout.splitlines()
    if len(demangled) != len(names):
        print(f"warning: rustfilt returned {len(demangled)} lines for {len(names)} names",
              file=sys.stderr)
    return dict(zip(names, demangled))


def get_functions(path, with_regions=False):
    """Return {stripped_demangled_name: info} for every function with count > 0.

    Key is the demangled name with generic args stripped, so all
    monomorphizations of one function collapse into one entry, but different
    functions NEVER merge (this replaces the old (filename, line_start) key,
    which could file a hit on fold_region under fold_const's name).

    With with_regions=True each info also carries 'regions':
    {(line_start, col_start, line_end, col_end): summed_count} across all
    monomorphizations, code regions (kind 0) only.
    """
    with open(path) as f:
        d = json.load(f)

    raw = []  # (mangled, count, filename, regions)
    for file in d['data']:
        for fn in file['functions']:
            if fn['count'] <= 0:
                continue
            filename = ''
            if fn.get('filenames'):
                filename = next(
                    (f for f in fn['filenames'] if '/compiler/' in f),
                    fn['filenames'][0]
                )
            regions = fn.get('regions', []) if with_regions else []
            raw.append((fn['name'], fn['count'], filename, regions))

    demangled = demangle_all([m for m, _, _, _ in raw])

    hit = {}
    for mangled, count, filename, regions in raw:
        name = strip_generics(demangled.get(mangled, mangled))
        info = hit.setdefault(name, {'count': 0, 'monos': 0, 'filename': filename,
                                     'regions': {}})
        info['count'] += count
        info['monos'] += 1
        for r in regions:
            # region: [line_start, col_start, line_end, col_end, count,
            #          file_id, expanded_file_id, kind]
            if r[7] != 0:  # code regions only
                continue
            key = (r[0], r[1], r[2], r[3])
            info['regions'][key] = info['regions'].get(key, 0) + r[4]
    return hit


def merge_lines(lines):
    """[3,4,5,9,10] -> '3-5, 9-10' for readable output."""
    lines = sorted(set(lines))
    ranges, start, prev = [], lines[0], lines[0]
    for l in lines[1:]:
        if l == prev + 1:
            prev = l
            continue
        ranges.append((start, prev))
        start = prev = l
    ranges.append((start, prev))
    return ', '.join(str(a) if a == b else f'{a}-{b}' for a, b in ranges)


args = [a for a in sys.argv[1:] if a != '--lines']
line_mode = '--lines' in sys.argv

if len(args) != 2:
    print("usage: diff_coverage.py [--lines] <crate-coverage.json> <suite-coverage.json>")
    print("  --lines: also report partially-covered functions (hit by both, but")
    print("           the crate covers regions/lines inside that the suite misses)")
    sys.exit(1)

crate_hit = get_functions(args[0], with_regions=line_mode)
suite_hit = get_functions(args[1], with_regions=line_mode)

gaps = {}
for name, info in crate_hit.items():
    if name in suite_hit:
        continue
    if any(noise in name for noise in NOISE_DEMANGLED):
        continue
    gaps[name] = info

print(f"hit by crate: {len(crate_hit)}")
print(f"hit by test suite: {len(suite_hit)}")
print(f"hit by crate but NOT test suite: {len(gaps)}")
print()

for name, info in sorted(gaps.items(), key=lambda kv: -kv[1]['count']):
    print(f"count={info['count']} monos={info['monos']} {name}")
    if info['filename']:
        print(f"    {info['filename']}")

if line_mode:
    # functions hit by BOTH, but the crate covers regions the suite misses
    partial = {}
    for name, cinfo in crate_hit.items():
        sinfo = suite_hit.get(name)
        if sinfo is None:
            continue  # whole-function gap, already reported above
        if any(noise in name for noise in NOISE_DEMANGLED):
            continue
        missed = [(key, cnt) for key, cnt in cinfo['regions'].items()
                  if cnt > 0 and sinfo['regions'].get(key, 0) == 0]
        if missed:
            partial[name] = (cinfo, missed)

    print()
    print(f"partially-covered functions (crate hits lines the suite misses): {len(partial)}")
    print()

    def missed_weight(item):
        return -sum(cnt for _, cnt in item[1][1])

    for name, (cinfo, missed) in sorted(partial.items(), key=missed_weight):
        lines = [key[0] for key, _ in missed]
        total = sum(cnt for _, cnt in missed)
        print(f"regions_missed={len(missed)} crate_hits_in_them={total} {name}")
        if cinfo['filename']:
            print(f"    {cinfo['filename']}")
        print(f"    lines: {merge_lines(lines)}")
