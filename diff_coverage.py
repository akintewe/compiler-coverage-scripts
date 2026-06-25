import json, subprocess, sys

def get_hit_functions(path):
    with open(path) as f:
        d = json.load(f)
    hit = set()
    for file in d['data']:
        for fn in file['functions']:
            if fn['count'] > 0:
                hit.add(fn['name'])
    return hit

if len(sys.argv) != 3:
    print("usage: diff_coverage.py <crate-coverage.json> <suite-coverage.json>")
    sys.exit(1)

crate_hit = get_hit_functions(sys.argv[1])
suite_hit = get_hit_functions(sys.argv[2])

only_in_crate = sorted(crate_hit - suite_hit)
print(f"hit by crate: {len(crate_hit)}")
print(f"hit by test suite: {len(suite_hit)}")
print(f"hit by crate but NOT test suite: {len(only_in_crate)}")
print()
names = '\n'.join(only_in_crate)
result = subprocess.run(['rustfilt'], input=names, capture_output=True, text=True)
print(result.stdout)
