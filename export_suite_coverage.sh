#!/bin/bash
# Turns a .profdata file into a filtered coverage.json, the same shape
# build_crates_batch.sh produces per crate. Also what turns the compiler's
# own baseline test-suite run into its coverage.json.
# Usage: ./export_suite_coverage.sh <profdata> <output.json>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
require_stage1

PROFDATA=$1
OUTPUT=$2
DRIVER=$(find_driver)

"$LLVM_COV" export \
  --format=text \
  --instr-profile="$PROFDATA" \
  "$STAGE1" \
  --object "$DRIVER" \
  | python3 "$FILTER_COV" > "$OUTPUT"

echo "=== done: $OUTPUT ==="
