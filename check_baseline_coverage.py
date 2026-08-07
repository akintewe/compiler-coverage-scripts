#!/usr/bin/env python3
"""Check whether a specific line is covered in a baseline coverage JSON.
Usage: python3 check_baseline_coverage.py <baseline.json> <file> <line>
Prints "covered" or "uncovered".
"""
import json
import sys

suite_json, target_file, target_line = sys.argv[1], sys.argv[2], int(sys.argv[3])

with open(suite_json) as f:
    data = json.load(f)

for file in data['data']:
    for fn in file['functions']:
        if fn['count'] <= 0:
            continue
        for r in fn['regions']:
            if len(r) < 5:
                continue
            if int(r[0]) != target_line:
                continue
            if any(target_file in name for name in fn['filenames']):
                print('covered')
                sys.exit()

print('uncovered')
