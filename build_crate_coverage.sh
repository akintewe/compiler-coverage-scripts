#!/bin/bash
# Usage: ./build_crate_coverage.sh <crate-dir> <output-dir>
# Example: ./build_crate_coverage.sh ~/crate-coverage/either-test ~/crate-coverage/either-profraws

set -e

CRATE_DIR=$1
OUTPUT_DIR=$2
STAGE1=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1/bin/rustc
LLVM_PROFDATA=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/ci-llvm/bin/llvm-profdata
LLVM_COV=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/ci-llvm/bin/llvm-cov
DRIVER=$(ls /home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1/lib/librustc_driver-*.so)

mkdir -p $OUTPUT_DIR/profraws

echo "=== cargo build ==="
cd $CRATE_DIR
LLVM_PROFILE_FILE=$OUTPUT_DIR/profraws/default_%m_%p.profraw \
RUSTC=$STAGE1 \
cargo build

echo "=== cargo test --no-run ==="
LLVM_PROFILE_FILE=$OUTPUT_DIR/profraws/default_%m_%p.profraw \
RUSTC=$STAGE1 \
cargo test --no-run

echo "=== merging profraws ==="
$LLVM_PROFDATA merge --sparse -o $OUTPUT_DIR/crate.profdata $OUTPUT_DIR/profraws/*.profraw

echo "=== running llvm-cov ==="
$LLVM_COV export \
  --format=text \
  --instr-profile=$OUTPUT_DIR/crate.profdata \
  $STAGE1 \
  --object $DRIVER \
  | python3 ~/filter_cov.py > $OUTPUT_DIR/coverage.json

echo "=== done: $OUTPUT_DIR/coverage.json ==="
