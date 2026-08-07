#!/bin/bash
# Builds a batch of crates with the instrumented rustc and generates coverage JSON for each.
# Usage: ./build_crates_batch.sh <output-subfolder> <crate1> <crate2> ...

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
require_stage1

OUT_SUBFOLDER=$1
shift
CRATES="$@"

OUTPUT_BASE=$COVERAGE_OUT/$OUT_SUBFOLDER
CRATE_WORKDIR=$WORKDIR/$OUT_SUBFOLDER
DRIVER=$(find_driver)

mkdir -p "$CRATE_WORKDIR"

for CRATE in $CRATES; do
    echo "=== $CRATE ==="

    CRATE_SRC=$(ls -d "$REGISTRY/${CRATE}-"* 2>/dev/null | sort -V | tail -1)
    if [ -z "$CRATE_SRC" ]; then
        echo "  skipping $CRATE: not found in registry cache"
        continue
    fi

    # copy to writable location
    CRATE_DIR=$CRATE_WORKDIR/$CRATE
    rm -rf "$CRATE_DIR"
    cp -r "$CRATE_SRC" "$CRATE_DIR"
    chmod -R u+w "$CRATE_DIR"

    echo "  using $CRATE_DIR"

    OUT_DIR=$OUTPUT_BASE/$CRATE
    mkdir -p "$OUT_DIR/profraws"

    cd "$CRATE_DIR"

    # build deps first without profiling (caches them)
    if ! RUSTC=$STAGE1 cargo build 2>&1; then
        echo "  WARNING: $CRATE failed to build, skipping"
        continue
    fi
    RUSTC=$STAGE1 cargo test --no-run 2>&1 || true

    # force recompile of the crate root only, not its dependencies. Only
    # bother if there's a root file to touch. Crates that are bin-only
    # have no src/lib.rs, and creating one would change what cargo builds.
    if [ -f src/lib.rs ]; then
        ROOT=src/lib.rs
    elif [ -f src/main.rs ]; then
        ROOT=src/main.rs
    else
        ROOT=""
    fi
    [ -n "$ROOT" ] && touch "$ROOT"

    # collect coverage for root crate only
    if ! LLVM_PROFILE_FILE=$OUT_DIR/profraws/default_%m_%p.profraw \
    RUSTC=$STAGE1 cargo build 2>&1; then
        echo "  WARNING: $CRATE failed to build under coverage, skipping"
        continue
    fi

    [ -n "$ROOT" ] && touch "$ROOT"

    LLVM_PROFILE_FILE=$OUT_DIR/profraws/default_%m_%p.profraw \
    RUSTC=$STAGE1 cargo test --no-run 2>&1 || true

    ls "$OUT_DIR"/profraws/*.profraw > /dev/null 2>&1 || { echo "  WARNING: no profraws written for $CRATE"; continue; }

    "$LLVM_PROFDATA" merge --sparse -o "$OUT_DIR/crate.profdata" "$OUT_DIR"/profraws/*.profraw

    "$LLVM_COV" export \
      --format=text \
      --instr-profile="$OUT_DIR/crate.profdata" \
      "$STAGE1" \
      --object "$DRIVER" \
      | python3 "$FILTER_COV" > "$OUT_DIR/coverage.json"

    echo "=== done: $CRATE ==="
done
