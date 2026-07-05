import json, subprocess, sys

def get_hit_functions(path):
    with open(path) as f:
        d = json.load(f)
    hit = set()
    for file in d['data']:
        for fn in file['functions']:
            if not fn['filenames'] or not fn['regions']:
                continue
            filename = next(
                (f for f in fn['filenames'] if '/compiler/' in f),
                fn['filenames'][0]
            )
            line_start = None
            for region in fn['regions']:
                if len(region) < 5:
                    continue
                rs = region[0] if isinstance(region[0], int) else int(region[0])
                if rs > 0 and (line_start is None or rs < line_start):
                    line_start = rs
            if line_start is None:
                continue
            if fn['count'] > 0:
                hit.add((filename, line_start))
    return hit

def get_representative_names(path, keys):
    with open(path) as f:
        d = json.load(f)
    names = {}
    for file in d['data']:
        for fn in file['functions']:
            if not fn['filenames'] or not fn['regions']:
                continue
            filename = next(
                (f for f in fn['filenames'] if '/compiler/' in f),
                fn['filenames'][0]
            )
            line_start = None
            for region in fn['regions']:
                if len(region) < 5:
                    continue
                rs = region[0] if isinstance(region[0], int) else int(region[0])
                if rs > 0 and (line_start is None or rs < line_start):
                    line_start = rs
            if line_start is None:
                continue
            key = (filename, line_start)
            if key in keys and key not in names:
                names[key] = fn['name']
    return names

if len(sys.argv) != 3:
    print("usage: diff_coverage.py <crate-coverage.json> <suite-coverage.json>")
    sys.exit(1)

crate_hit = get_hit_functions(sys.argv[1])
suite_hit = get_hit_functions(sys.argv[2])
only_in_crate = crate_hit - suite_hit

print(f"hit by crate: {len(crate_hit)}")
print(f"hit by test suite: {len(suite_hit)}")
print(f"hit by crate but NOT test suite: {len(only_in_crate)}")
print()

if only_in_crate:
    names = get_representative_names(sys.argv[1], only_in_crate)
    mangled = '\n'.join(names.get(k, '') for k in sorted(only_in_crate) if names.get(k))
    result = subprocess.run(['rustfilt'], input=mangled, capture_output=True, text=True)
    print(result.stdout)
