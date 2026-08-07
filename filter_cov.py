#!/usr/bin/env python3
"""Keep only functions that actually live in the compiler source tree.

llvm-cov export dumps every function the profiled binary ever touched,
which is the standard library, every dependency, and the compiler all
mixed together. Filtering by file path (does it live under /compiler/)
instead of by name works even for a dependency like rustc-hash, whose
name starts with the same letters as the real rustc_* crates but is not
part of the compiler at all.
"""
import json
import sys

data = json.load(sys.stdin)

for file in data['data']:
    file['functions'] = [
        fn for fn in file['functions']
        if any('/compiler/' in name for name in fn.get('filenames', []))
    ]

json.dump(data, sys.stdout)
