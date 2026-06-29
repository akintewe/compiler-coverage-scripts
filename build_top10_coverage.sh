#!/bin/bash
# Builds each of the top 10 crates with the instrumented rustc and generates coverage JSON.
# Uses the crate source from ~/.cargo/registry/src/ (downloaded by cargo automatically).
# Outputs go to /var/tmp/jackh726_akintewe_codecoverage/top10_crates/<crate-name>/

set -e

CRATES="syn hashbrown getrandom bitflags rand_core rand libc proc-macro2 quote base64"
OUTPUT_BASE=/var/tmp/jackh726_akintewe_codecoverage/top10_crates
REGISTRY=~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f
STAGE1=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1/bin/rustc
LLVM_PROFDATA=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/ci-llvm/bin/llvm-profdata
LLVM_COV=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/ci-llvm/bin/llvm-cov
DRIVER=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1-rustc/aarch64-unknown-linux-gnu/release/deps/librustc_driver-10d726a819bd0aa8.so

for CRATE in $CRATES; do
    echo "=== $CRATE ==="

    # find the latest version in the registry cache
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
