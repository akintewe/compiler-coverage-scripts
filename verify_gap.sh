#!/bin/bash
# Used by cargo-minimize as the verify function.
# Returns 0 (success/keep minimizing) if the panic fires when compiling with instrumented rustc.
# Returns 1 (failure/stop) if it doesn't fire.

STAGE1=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1/bin/rustc

output=$(RUSTC=$STAGE1 cargo build 2>&1)

if echo "$output" | grep -q "coverage check:"; then
    exit 0  # panic fired -- gap still present, keep minimizing
else
    exit 1  # panic didn't fire -- minimization removed the trigger
fi
