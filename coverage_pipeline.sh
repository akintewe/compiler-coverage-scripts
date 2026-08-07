#!/bin/bash
# Coverage pipeline: takes a list of crates, runs coverage on each,
# diffs against the test suite, writes out gaps.
# Usage: ./coverage_pipeline.sh <suite-coverage.json> <crate1> <crate2> ...

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
require_stage1

SUITE_JSON=$1
shift
CRATES="$@"

DRIVER=$(find_driver)
PIPELINE_WORKDIR=$WORKDIR/pipeline
OUTPUT=$COVERAGE_OUT/pipeline_results

mkdir -p "$PIPELINE_WORKDIR" "$OUTPUT"

SUMMARY=$OUTPUT/summary.txt
echo "Coverage pipeline run $(date)" > "$SUMMARY"
echo "Suite baseline: $SUITE_JSON" >> "$SUMMARY"
echo "---" >> "$SUMMARY"

for CRATE in $CRATES; do
    echo "=== $CRATE ==="

    CRATE_SRC=$(ls -d "$REGISTRY/${CRATE}-"* 2>/dev/null | sort -V | tail -1)
    if [ -z "$CRATE_SRC" ]; then
        echo "  skipping $CRATE: not in registry cache"
        echo "$CRATE: SKIPPED (not in registry cache)" >> "$SUMMARY"
        continue
    fi

    CRATE_DIR=$PIPELINE_WORKDIR/$CRATE
    PROFRAW_DIR=$PIPELINE_WORKDIR/${CRATE}_profraws
    rm -rf "$CRATE_DIR" "$PROFRAW_DIR"
    cp -r "$CRATE_SRC" "$CRATE_DIR"
    chmod -R u+w "$CRATE_DIR"
    mkdir -p "$PROFRAW_DIR"

    cd "$CRATE_DIR"

    if ! LLVM_PROFILE_FILE=$PROFRAW_DIR/default_%m_%p.profraw \
    RUSTC=$STAGE1 cargo build 2>/dev/null; then
        echo "  WARNING: $CRATE failed to build"
        echo "$CRATE: FAILED (build error)" >> "$SUMMARY"
        continue
    fi

    LLVM_PROFILE_FILE=$PROFRAW_DIR/default_%m_%p.profraw \
    RUSTC=$STAGE1 cargo test --no-run 2>/dev/null || true

    if ls "$PROFRAW_DIR"/*.profraw > /dev/null 2>&1; then
        "$LLVM_PROFDATA" merge --sparse -o "$PROFRAW_DIR/crate.profdata" "$PROFRAW_DIR"/*.profraw

        "$LLVM_COV" export \
          --format=text \
          --instr-profile="$PROFRAW_DIR/crate.profdata" \
          "$STAGE1" --object "$DRIVER" \
          | python3 "$FILTER_COV" > "$OUTPUT/${CRATE}_coverage.json"

        GAPS=$(python3 "$SCRIPT_DIR/diff_coverage.py" \
          "$OUTPUT/${CRATE}_coverage.json" \
          "$SUITE_JSON" 2>/dev/null | grep "hit by crate but NOT" | awk '{print $NF}')
        GAPS=${GAPS:-0}

        echo "$CRATE: $GAPS gaps" >> "$SUMMARY"

        if [ "$GAPS" -gt "0" ]; then
            python3 "$SCRIPT_DIR/diff_coverage.py" \
              "$OUTPUT/${CRATE}_coverage.json" \
              "$SUITE_JSON" 2>/dev/null > "$OUTPUT/${CRATE}_gaps.txt"
            echo "  $GAPS gaps found, saved to ${CRATE}_gaps.txt"
        else
            echo "  0 gaps"
        fi

        # clean up profraws to save space
        rm -rf "$PROFRAW_DIR"
    else
        echo "  WARNING: no profraws written"
        echo "$CRATE: FAILED (no profraws)" >> "$SUMMARY"
    fi
done

echo "---" >> "$SUMMARY"
echo "Done. Results in $OUTPUT" >> "$SUMMARY"
cat "$SUMMARY"
