#!/usr/bin/env python3
"""
Adds a panic to a Rust function for coverage validation.
Usage: python3 add_panic.py <file> <function_line> <panic_message>
Finds the opening brace of the function body and inserts the panic after it.
"""
import sys

filepath = sys.argv[1]
func_line = int(sys.argv[2])  # 1-indexed
panic_msg = sys.argv[3]

with open(filepath) as f:
    lines = f.readlines()

# find the line with the opening brace of the function body
# skip lines that are part of the parameter list (indented)
# the body opening brace is on a line starting with `) ->` or on a `{` alone
body_open = None
depth = 0
for i in range(func_line - 1, len(lines)):
    line = lines[i]
    for ch in line:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
    if depth <= 0 and '{' in line:
        body_open = i  # 0-indexed
        break

if body_open is None:
    print(f"ERROR: could not find function body opening brace after line {func_line}")
    sys.exit(1)

print(f"Function body opens at line {body_open + 1}")

# insert allow before function and panic after opening brace
lines.insert(func_line - 1, f'#[allow(unreachable_code, unused_variables)]\n')
# body_open shifted by 1 due to insertion
actual_body_open = body_open + 1
lines.insert(actual_body_open + 1, f'    panic!("{panic_msg}");\n')

with open(filepath, 'w') as f:
    f.writelines(lines)

print("Done.")
