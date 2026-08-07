#!/bin/bash
# Builds each of the top 10 crates from top10_crates.txt with the
# instrumented rustc. Just build_crates_batch.sh with that list baked in,
# so there's one place the list lives, not two.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRATES=$(grep -v '^#' "$SCRIPT_DIR/top10_crates.txt")

exec "$SCRIPT_DIR/build_crates_batch.sh" top10_crates $CRATES
