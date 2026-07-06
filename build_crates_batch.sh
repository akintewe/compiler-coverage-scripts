#!/bin/bash
# Builds a batch of crates with the instrumented rustc and generates coverage JSON for each.
# Usage: ./build_crates_batch.sh <output-subfolder> <crate1> <crate2> ...

set -e

OUT_SUBFOLDER=$1
shift
CRATES="$@"

OUTPUT_BASE=/var/tmp/jackh726_akintewe_codecoverage/$OUT_SUBFOLDER
REGISTRY=~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f
STAGE1=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1/bin/rustc
LLVM_PROFDATA=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/ci-llvm/bin/llvm-profdata
LLVM_COV=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/ci-llvm/bin/llvm-covDRIVER=$(ls -S /home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1-rustc/aarch64-unknown-linux-gnu/release/deps/librustc_driver-*.so | head -1)
DRIVER=$(ls /home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1-rustc/aarch64-unknown-linux-gnu/release/deps/librustc_driver-*.so | sort -V | tail -1)
WORKDIR=/home/gh-akintewe/crate-coverage/uncommon

mkdir -p $WORKDIR

for CRATE in $CRATES; do
    echo "=== $CRATE ==="

    CRATE_SRC=$(ls -d $REGISTRY/${CRATE}-* 2>/dev/null | sort -V | tail -1)
    if [ -z "$CRATE_SRC" ]; then
        echo "  skipping $CRATE: not found in registry cache"
        continue
    fi

    # copy to writable location
    CRATE_DIR=$WORKDIR/$CRATE
    rm -rf $CRATE_DIR
    cp -r $CRATE_SRC $CRATE_DIR
    chmod -R u+w $CRATE_DIR

    echo "  using $CRATE_DIR"

    OUT_DIR=$OUTPUT_BASE/$CRATE
    mkdir -p $OUT_DIR/profraws

    cd $CRATE_DIR

    LLVM_PROFILE_FILE=$OUT_DIR/profraws/default_%m_%p.profraw \
    RUSTC=$STAGE1 cargo build 2>&1 || true

    LLVM_PROFILE_FILE=$OUT_DIR/profraws/default_%m_%p.profraw \
    RUSTC=$STAGE1 cargo test --no-run 2>&1 || true

    ls $OUT_DIR/profraws/*.profraw > /dev/null 2>&1 || { echo "  WARNING: no profraws written for $CRATE"; continue; }

    $LLVM_PROFDATA merge --sparse -o $OUT_DIR/crate.profdata $OUT_DIR/profraws/*.profraw

    $LLVM_COV export \
      --format=text \
      --instr-profile=$OUT_DIR/crate.profdata \
      $STAGE1 \
      --object $DRIVER \
      | python3 ~/filter_cov.py > $OUT_DIR/coverage.json

    echo "=== done: $CRATE ==="
done
