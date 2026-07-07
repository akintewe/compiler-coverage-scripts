import json, subprocess, sys

def get_functions(path):
    with open(path) as f:
        d = json.load(f)
    # maps (filename, line_start) -> set of mangled names with count > 0
    hit = {}
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
                key = (filename, line_start)
                hit.setdefault(key, set()).add(fn['name'])
    return hit

if len(sys.argv) != 3:
    print("usage: diff_coverage.py <crate-coverage.json> <suite-coverage.json>")
    sys.exit(1)

crate_hit = get_functions(sys.argv[1])
suite_hit = get_functions(sys.argv[2])

# a gap is a (filename, line_start) where:
# - at least one function name is hit in the crate
# - none of those same function names are hit in the suite
gaps = {}
for key, crate_names in crate_hit.items():
    suite_names = suite_hit.get(key, set())
    uncovered_names = crate_names - suite_names
    if uncovered_names:
        gaps[key] = uncovered_names

print(f"hit by crate: {len(crate_hit)}")
print(f"hit by test suite: {len(suite_hit)}")
print(f"hit by crate but NOT test suite: {len(gaps)}")
print()

if gaps:
    mangled = '\n'.join(
        name for names in gaps.values() for name in names
    )
    result = subprocess.run(['rustfilt'], input=mangled, capture_output=True, text=True)
    print(result.stdout)
