#!/bin/bash
CRATE_DIR=$1
FUNCTION_FILE=$2
FUNCTION_LINE=$3
PANIC_MSG=$4
SUITE_JSON=${5:-/var/tmp/jackh726_akintewe_codecoverage/compiler_ui_coverage/fresh-coverage-july1.json}
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

echo "Verifying function is uncovered in baseline JSON..."
COVERED=$(python3 -c "
import json
with open('$SUITE_JSON') as f:
    d = json.load(f)
for file in d['data']:
    for fn in file['functions']:
        if fn['count'] > 0:
            for r in fn['regions']:
                if len(r) >= 5:
                    rs = r[0] if isinstance(r[0], int) else int(r[0])
                    if rs == $FUNCTION_LINE:
                        for fname in fn['filenames']:
                            if '$FUNCTION_FILE' in fname:
                                print('covered')
                                exit()
print('uncovered')
" 2>/dev/null)
if [ "$COVERED" = "covered" ]; then
    echo "  WARNING: function is covered in baseline -- not a real gap"
    exit 1
else
    echo "  GOOD: function is uncovered in baseline"
fi

echo "Running cargo-minimize..."
cd $CRATE_COPY
RUSTC=$STAGE1 cargo minimize \
    --verify-fn='|output| output.out.contains("'"$PANIC_MSG"'")' \
    --cargo-subcmd="build"

echo "=== Done. Minimized code is in $CRATE_COPY/src/ ==="
echo "Lines: $(wc -l < $CRATE_COPY/src/lib.rs 2>/dev/null || echo 'unknown')"
