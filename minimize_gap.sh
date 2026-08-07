#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
require_stage1

CRATE_DIR=$1
FUNCTION_FILE=$2
FUNCTION_LINE=$3
PANIC_MSG=$4
SUITE_JSON=${5:-$COVERAGE_OUT/compiler_ui_coverage/fresh-coverage-july1.json}
CRATE_NAME=$(basename "$CRATE_DIR")
TARGET_FILE=$RUST_SRC/$FUNCTION_FILE
MINIMIZE_WORKDIR=$WORKDIR/minimize

# We're about to edit TARGET_FILE and revert it on exit. If it already has
# uncommitted changes, our revert would throw those away along with our
# own edit, and we'd have no way to tell them apart. Refuse instead.
cd "$RUST_SRC"
if [ -n "$(git status --porcelain -- "$FUNCTION_FILE")" ]; then
    echo "ERROR: $FUNCTION_FILE already has uncommitted changes, refusing to touch it" >&2
    echo "  commit or stash your changes first" >&2
    exit 1
fi

cleanup() {
    echo "Restoring compiler..."
    cd "$RUST_SRC" && git checkout "$FUNCTION_FILE" 2>/dev/null || true
}
trap cleanup EXIT

set -e

echo "=== Minimization pipeline for gap in $CRATE_NAME ==="
echo "Target: $FUNCTION_FILE:$FUNCTION_LINE"

echo "Adding panic to $TARGET_FILE..."
python3 "$SCRIPT_DIR/add_panic.py" "$TARGET_FILE" "$FUNCTION_LINE" "$PANIC_MSG"

echo "Rebuilding stage1..."
cd "$RUST_SRC"
python3 x.py build --stage 1 2>&1 | tail -5

echo "Preparing crate copy..."
CRATE_COPY=$MINIMIZE_WORKDIR/${CRATE_NAME}_minimize
rm -rf "$CRATE_COPY"
cp -r "$CRATE_DIR" "$CRATE_COPY"
chmod -R u+w "$CRATE_COPY"

echo "Verifying panic fires on crate..."
cd "$CRATE_COPY"
set +e
RESULT=$(RUSTC=$STAGE1 cargo build 2>&1)
set -e
if echo "$RESULT" | grep -q "$PANIC_MSG"; then
    echo "  GOOD: panic fires on crate"
else
    echo "  ERROR: panic does not fire on crate"
    exit 1
fi

echo "Verifying function is uncovered in baseline JSON..."
COVERED=$(python3 "$SCRIPT_DIR/check_baseline_coverage.py" "$SUITE_JSON" "$FUNCTION_FILE" "$FUNCTION_LINE")
if [ "$COVERED" = "covered" ]; then
    echo "  WARNING: function is covered in baseline, not a real gap"
    exit 1
else
    echo "  GOOD: function is uncovered in baseline"
fi

echo "Running cargo-minimize..."
cd "$CRATE_COPY"
RUSTC=$STAGE1 cargo minimize \
    --verify-fn='|output| output.out.contains("'"$PANIC_MSG"'")' \
    --cargo-subcmd="build"

echo "=== Done. Minimized code is in $CRATE_COPY/src/ ==="
echo "Lines: $(wc -l < "$CRATE_COPY/src/lib.rs" 2>/dev/null || echo 'unknown')"
