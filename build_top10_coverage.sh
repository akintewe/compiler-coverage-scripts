#!/bin/bash
# Builds each of the top 10 crates with the instrumented rustc and generates coverage JSON.
# Outputs go to /var/tmp/jackh726_akintewe_codecoverage/top10_crates/<crate-name>/

set -e

CRATES="syn hashbrown getrandom bitflags rand_core rand libc proc-macro2 quote base64"
OUTPUT_BASE=/var/tmp/jackh726_akintewe_codecoverage/top10_crates
STAGE1=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1/bin/rustc
LLVM_PROFDATA=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/ci-llvm/bin/llvm-profdata
LLVM_COV=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/ci-llvm/bin/llvm-cov
DRIVER=/home/gh-akintewe/rust/build/aarch64-unknown-linux-gnu/stage1-rustc/aarch64-unknown-linux-gnu/release/deps/librustc_driver-10d726a819bd0aa8.so
WORKDIR=/home/gh-akintewe/crate-coverage/top10

mkdir -p $WORKDIR

for CRATE in $CRATES; do
    echo "=== $CRATE ==="
    CRATE_DIR=$WORKDIR/$CRATE
    OUT_DIR=$OUTPUT_BASE/$CRATE

    mkdir -p $CRATE_DIR $OUT_DIR/profraws

    cd $CRATE_DIR
    if [ ! -f Cargo.toml ]; then
        cargo init --name ${CRATE}_test
        sed -i "s/^name = .*/name = \"${CRATE}_test\"/" Cargo.toml
        cargo add $CRATE
        echo "fn main() {}" > src/main.rs
    fi

    LLVM_PROFILE_FILE=$OUT_DIR/profraws/default_%m_%p.profraw \
    RUSTC=$STAGE1 cargo build

    LLVM_PROFILE_FILE=$OUT_DIR/profraws/default_%m_%p.profraw \
    RUSTC=$STAGE1 cargo test --no-run

    $LLVM_PROFDATA merge --sparse -o $OUT_DIR/crate.profdata $OUT_DIR/profraws/*.profraw

    $LLVM_COV export \
      --format=text \
      --instr-profile=$OUT_DIR/crate.profdata \
      $STAGE1 \
      --object $DRIVER \
      | python3 ~/filter_cov.py > $OUT_DIR/coverage.json

    echo "=== done: $CRATE ==="
done
