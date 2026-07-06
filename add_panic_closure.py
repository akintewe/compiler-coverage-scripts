#!/usr/bin/env python3
"""
Replaces a specific line in a Rust file with a version that includes a panic.
Usage: python3 add_panic_closure.py <file> <line-number> <old-text> <new-text>
"""
import sys

filepath = sys.argv[1]
line_num = int(sys.argv[2])  # 1-indexed
old_text = sys.argv[3]
new_text = sys.argv[4]

with open(filepath) as f:
    lines = f.readlines()

line = lines[line_num - 1]
if old_text not in line:
    print(f"ERROR: '{old_text}' not found on line {line_num}")
    print(f"Line content: {line.rstrip()}")
    sys.exit(1)

lines[line_num - 1] = line.replace(old_text, new_text)
with open(filepath, 'w') as f:
    f.writelines(lines)

print(f"Done. Replaced on line {line_num}.")
