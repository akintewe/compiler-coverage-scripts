#!/bin/bash
# Builds a batch of crates with the instrumented rustc and generates coverage JSON for each.
# Usage: ./build_crates_batch.sh <output-subfolder> <crate1> <crate2> ...
# Example: ./build_crates_batch.sh outside_top10 serde serde_derive regex-syntax

set -e

OUT_SUBFOLDER=$1
shift
CRATES="$@"

OUTPUT_BASE=/var/tmp/jackh726_akintewe_codecoverage/$OUT_SUBFOLDER
REGISTRY=~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f
STAGE1=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1/bin/rustc
LLVM_PROFDATA=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/ci-llvm/bin/llvm-profdata
LLVM_COV=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/ci-llvm/bin/llvm-cov
DRIVER=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1-rustc/aarch64-unknown-linux-gnu/release/deps/librustc_driver-10d726a819bd0aa8.so

for CRATE in $CRATES; do
    echo "=== $CRATE ==="

    # download the crate if not already cached
    mkdir -p /tmp/fetch-$CRATE && cd /tmp/fetch-$CRATE
    if [ ! -f Cargo.toml ]; then
        cargo init --name fetch_${CRATE//-/_} > /dev/null 2>&1
        cargo add $CRATE > /dev/null 2>&1 || { echo "  failed to add $CRATE, skipping"; continue; }
    fi

    CRATE_DIR=$(ls -d $REGISTRY/${CRATE}-* 2>/dev/null | sort -V | tail -1)
    if [ -z "$CRATE_DIR" ]; then
        echo "  skipping $CRATE: not found in registry cache"
        continue
    fi
    echo "  using $CRATE_DIR"

    OUT_DIR=$OUTPUT_BASE/$CRATE
    mkdir -p $OUT_DIR/profraws

    cd $CRATE_DIR

    LLVM_PROFILE_FILE=$OUT_DIR/profraws/default_%m_%p.profraw \
    RUSTC=$STAGE1 cargo build 2>&1 || true

    LLVM_PROFILE_FILE=$OUT_DIR/profraws/default_%m_%p.profraw \
    RUSTC=$STAGE1 cargo test --no-run 2>&1 || true

    $LLVM_PROFDATA merge --sparse -o $OUT_DIR/crate.profdata $OUT_DIR/profraws/*.profraw

    $LLVM_COV export \
      --format=text \
      --instr-profile=$OUT_DIR/crate.profdata \
      $STAGE1 \
      --object $DRIVER \
      | python3 ~/filter_cov.py > $OUT_DIR/coverage.json

    echo "=== done: $CRATE ==="
done
