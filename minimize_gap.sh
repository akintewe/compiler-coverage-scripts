#!/bin/bash
# Minimization pipeline for a compiler coverage gap.
# Usage: ./minimize_gap.sh <crate-dir> <function-file> <function-line> <panic-message>

set -e

CRATE_DIR=$1
FUNCTION_FILE=$2
FUNCTION_LINE=$3
PANIC_MSG=$4
RUST_SRC=/home/gh-akintewe/rust
STAGE1=$RUST_SRC/build/aarch64-unknown-linux-gnu/stage1/bin/rustc
WORKDIR=/home/gh-akintewe/crate-coverage/minimize
CRATE_NAME=$(basename $CRATE_DIR)

echo "=== Minimization pipeline for gap in $CRATE_NAME ==="
echo "Target: $FUNCTION_FILE:$FUNCTION_LINE"

# Step 1: find the opening brace of the function body
TARGET_FILE=$RUST_SRC/$FUNCTION_FILE
BODY_LINE=$(awk "NR>=$FUNCTION_LINE && /^\{/{print NR; exit}" $TARGET_FILE)
if [ -z "$BODY_LINE" ]; then
    # function body starts with { at end of signature line
    BODY_LINE=$(awk "NR>=$FUNCTION_LINE && /\{/{print NR; exit}" $TARGET_FILE)
fi
echo "Function body opens at line $BODY_LINE"

# Step 2: add allow before function, panic as first line of body
echo "Adding panic to $TARGET_FILE..."
sed -i "${FUNCTION_LINE}i\\#[allow(unreachable_code, unused_variables)]" $TARGET_FILE
PANIC_INSERT=$((BODY_LINE + 1))
sed -i "${PANIC_INSERT}i\\    panic!(\"${PANIC_MSG}\");" $TARGET_FILE

# Step 3: rebuild stage1
echo "Rebuilding stage1..."
cd $RUST_SRC
python3 x.py build --stage 1 2>&1 | tail -5

# Step 4: verify panic fires on crate
echo "Verifying panic fires on crate..."
CRATE_COPY=$WORKDIR/${CRATE_NAME}_minimize
rm -rf $CRATE_COPY
cp -r $CRATE_DIR $CRATE_COPY
chmod -R u+w $CRATE_COPY
cd $CRATE_COPY

RESULT=$(RUSTC=$STAGE1 cargo build 2>&1)
if echo "$RESULT" | grep -q "$PANIC_MSG"; then
    echo "  GOOD: panic fires on crate"
else
    echo "  ERROR: panic does not fire on crate"
    cd $RUST_SRC && git checkout $FUNCTION_FILE
    exit 1
fi

# Step 5: verify panic does NOT fire on test suite
echo "Verifying panic does NOT fire on test suite..."
cd $RUST_SRC
SUITE_RESULT=$(python3 x.py test tests/ui/abi --stage 1 2>&1)
if echo "$SUITE_RESULT" | grep -q "$PANIC_MSG"; then
    echo "  WARNING: panic fires in test suite -- not a real gap"
    git checkout $FUNCTION_FILE
    exit 1
else
    echo "  GOOD: panic does not fire in test suite"
fi

# Step 6: run cargo-minimize
echo "Running cargo-minimize..."
cd $CRATE_COPY
RUSTC=$STAGE1 cargo minimize \
    --verify-fn="|output| output.contains(\"$PANIC_MSG\")" \
    --cargo-subcmd="build"

echo "=== Done. Minimized code is in $CRATE_COPY/src/ ==="

# Step 7: restore compiler
echo "Restoring compiler..."
cd $RUST_SRC && git checkout $FUNCTION_FILE
echo "Done."
