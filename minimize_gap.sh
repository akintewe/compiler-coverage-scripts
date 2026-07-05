#!/bin/bash
# Minimization pipeline for a compiler coverage gap.
# Usage: ./minimize_gap.sh <crate-dir> <function-file> <function-line> <panic-message>

CRATE_DIR=$1
FUNCTION_FILE=$2
FUNCTION_LINE=$3
PANIC_MSG=$4
RUST_SRC=/home/gh-akintewe/rust
STAGE1=$RUST_SRC/build/aarch64-unknown-linux-gnu/stage1/bin/rustc
WORKDIR=/home/gh-akintewe/crate-coverage/minimize
CRATE_NAME=$(basename $CRATE_DIR)
TARGET_FILE=$RUST_SRC/$FUNCTION_FILE

cleanup() {
    echo "Restoring compiler..."
    cd $RUST_SRC && git checkout $FUNCTION_FILE 2>/dev/null || true
}
trap cleanup EXIT

set -e

echo "=== Minimization pipeline for gap in $CRATE_NAME ==="
echo "Target: $FUNCTION_FILE:$FUNCTION_LINE"

echo "Adding panic to $TARGET_FILE..."
python3 ~/coverage-scripts/add_panic.py $TARGET_FILE $FUNCTION_LINE "$PANIC_MSG"

echo "Rebuilding stage1..."
cd $RUST_SRC
python3 x.py build --stage 1 2>&1 | tail -5

echo "Preparing crate copy..."
CRATE_COPY=$WORKDIR/${CRATE_NAME}_minimize
rm -rf $CRATE_COPY
cp -r $CRATE_DIR $CRATE_COPY
chmod -R u+w $CRATE_COPY

echo "Verifying panic fires on crate..."
cd $CRATE_COPY
set +e
RESULT=$(RUSTC=$STAGE1 cargo build 2>&1)
set -e
if echo "$RESULT" | grep -q "$PANIC_MSG"; then
    echo "  GOOD: panic fires on crate"
else
    echo "  ERROR: panic does not fire on crate"
    exit 1
fi

echo "Verifying panic does NOT fire on test suite..."
cd $RUST_SRC
set +e
SUITE_RESULT=$(python3 x.py test tests/ui/abi tests/ui/traits tests/ui/generics --stage 1 2>&1)
set -e
if echo "$SUITE_RESULT" | grep -q "$PANIC_MSG"; then
    echo "  WARNING: panic fires in test suite -- not a real gap"
    exit 1
else
    echo "  GOOD: panic does not fire in test suite"
fi

echo "Running cargo-minimize..."
cd $CRATE_COPY
RUSTC=$STAGE1 cargo minimize \
    --verify-fn='|output| output.out.contains("'"$PANIC_MSG"'")' \
    --cargo-subcmd="build"

echo "=== Done. Minimized code is in $CRATE_COPY/src/ ==="
echo "Lines: $(wc -l < $CRATE_COPY/src/lib.rs 2>/dev/null || echo 'unknown')"
