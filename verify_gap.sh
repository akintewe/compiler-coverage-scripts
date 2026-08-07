#!/bin/bash
# Alternative to the inline --verify-fn in minimize_gap.sh, for pointing
# cargo-minimize at a script instead of an inline closure.
# Returns 0 (success/keep minimizing) if the panic message shows up when
# compiling with the instrumented rustc, 1 (stop) if it doesn't.
# Usage: ./verify_gap.sh [panic-message]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

PANIC_MSG=${1:-"coverage check:"}

output=$(RUSTC=$STAGE1 cargo build 2>&1)

if echo "$output" | grep -q "$PANIC_MSG"; then
    exit 0  # panic fired, gap still present, keep minimizing
else
    exit 1  # panic didn't fire, minimization removed the trigger
fi
