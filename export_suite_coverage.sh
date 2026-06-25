#!/bin/bash
# Usage: ./export_suite_coverage.sh <profdata> <output.json>

set -e

PROFDATA=$1
OUTPUT=$2
STAGE1=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1/bin/rustc
LLVM_COV=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/ci-llvm/bin/llvm-cov
DRIVER=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1-rustc/aarch64-unknown-linux-gnu/release/deps/librustc_driver-10d726a819bd0aa8.so

$LLVM_COV export \
  --format=text \
  --instr-profile=$PROFDATA \
  $STAGE1 \
  --object $DRIVER \
  | python3 ~/filter_cov.py > $OUTPUT

echo "=== done: $OUTPUT ==="
