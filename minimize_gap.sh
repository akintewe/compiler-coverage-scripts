#!/bin/bash
# Minimization pipeline for a compiler coverage gap.
# Usage: ./minimize_gap.sh <crate-dir> <function-file> <function-line> <panic-message>
#
# Example:
#   ./minimize_gap.sh ~/.cargo/registry/src/.../log-0.4.22 \
#     compiler/rustc_codegen_llvm/src/debuginfo/metadata.rs \
#     699 \
#     "coverage check: build_cpp_f16_di_node"

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
echo "Panic message: $PANIC_MSG"

# Step 1: add panic to the function
TARGET_FILE=$RUST_SRC/$FUNCTION_FILE
PANIC_LINE=$((FUNCTION_LINE + 1))
echo "Adding panic to $TARGET_FILE line $PANIC_LINE..."
sed -i "${PANIC_LINE}i\\    #[allow(unreachable_code)] let _ = (); panic!(\"${PANIC_MSG}\");" $TARGET_FILE

# Step 2: rebuild stage1
echo "Rebuilding stage1..."
cd $RUST_SRC
python3 x.py build --stage 1 2>&1 | tail -5

# Step 3: verify panic fires on crate, not on test suite
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
    echo "  ERROR: panic does not fire on crate -- wrong function or line number"
    # restore the file
    cd $RUST_SRC && git checkout $FUNCTION_FILE
    exit 1
fi

echo "Verifying panic does NOT fire on test suite subset..."
cd $RUST_SRC
SUITE_RESULT=$(python3 x.py test tests/ui/abi --stage 1 2>&1 | tail -5)
if echo "$SUITE_RESULT" | grep -q "$PANIC_MSG"; then
    echo "  WARNING: panic fires in test suite -- function is already covered"
    git checkout $FUNCTION_FILE
    exit 1
else
    echo "  GOOD: panic does not fire in test suite"
fi

# Step 4: run cargo-minimize
echo "Running cargo-minimize..."
cd $CRATE_COPY
RUSTC=$STAGE1 cargo minimize \
    --verify-fn="|output| output.contains(\"$PANIC_MSG\")" \
    --cargo-subcmd="build"

echo "=== Done. Minimized code is in $CRATE_COPY/src/ ==="

# Step 5: restore compiler
echo "Restoring compiler..."
cd $RUST_SRC && git checkout $FUNCTION_FILE
echo "Done."
