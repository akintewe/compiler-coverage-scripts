#!/usr/bin/env python3
"""
Adds a panic to a Rust function or statement for coverage validation.
Usage: python3 add_panic.py <file> <target-line> <panic-message> [--inline]

Without --inline: finds the opening brace of the function starting at target-line
                  and inserts panic as first statement in function body.
With --inline:    inserts panic as a statement directly after target-line.
"""
import sys

filepath = sys.argv[1]
target_line = int(sys.argv[2])  # 1-indexed
panic_msg = sys.argv[3]
inline = len(sys.argv) > 4 and sys.argv[4] == '--inline'

with open(filepath) as f:
    lines = f.readlines()

if inline:
    # insert panic directly after the target line
    indent = len(lines[target_line - 1]) - len(lines[target_line - 1].lstrip())
    lines.insert(target_line, ' ' * indent + f'let _ = (|| -> bool {{ panic!("{panic_msg}"); }})();\n')
    print(f"Inserted inline panic after line {target_line}")
else:
    # find the opening brace of the function body
    depth = 0
    body_open = None
    for i in range(target_line - 1, len(lines)):
        line = lines[i]
        for ch in line:
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
        if depth <= 0 and '{' in line:
            body_open = i
            break

    if body_open is None:
        print(f"ERROR: could not find function body opening brace after line {target_line}")
        sys.exit(1)

    print(f"Function body opens at line {body_open + 1}")
    lines.insert(target_line - 1, f'#[allow(unreachable_code, unused_variables)]\n')
    actual_body_open = body_open + 1
    lines.insert(actual_body_open + 1, f'    panic!("{panic_msg}");\n')

with open(filepath, 'w') as f:
    f.writelines(lines)

print("Done.")
