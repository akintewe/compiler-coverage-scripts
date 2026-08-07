#!/bin/bash
# Usage: ./build_crate_coverage.sh <crate-dir> <output-dir>
# Example: ./build_crate_coverage.sh ~/crate-coverage/either-test ~/crate-coverage/either-profraws

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
require_stage1

CRATE_DIR=$1
OUTPUT_DIR=$2
DRIVER=$(find_driver)

mkdir -p "$OUTPUT_DIR/profraws"

echo "=== cargo build ==="
cd "$CRATE_DIR"
LLVM_PROFILE_FILE=$OUTPUT_DIR/profraws/default_%m_%p.profraw \
RUSTC=$STAGE1 \
cargo build

echo "=== cargo test --no-run ==="
LLVM_PROFILE_FILE=$OUTPUT_DIR/profraws/default_%m_%p.profraw \
RUSTC=$STAGE1 \
cargo test --no-run

echo "=== merging profraws ==="
"$LLVM_PROFDATA" merge --sparse -o "$OUTPUT_DIR/crate.profdata" "$OUTPUT_DIR"/profraws/*.profraw

echo "=== running llvm-cov ==="
"$LLVM_COV" export \
  --format=text \
  --instr-profile="$OUTPUT_DIR/crate.profdata" \
  "$STAGE1" \
  --object "$DRIVER" \
  | python3 "$FILTER_COV" > "$OUTPUT_DIR/coverage.json"

echo "=== done: $OUTPUT_DIR/coverage.json ==="
