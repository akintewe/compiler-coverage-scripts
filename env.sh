# Shared config for every script in this repo. Source it, don't run it.
#
# Everything here has a default that matches how this was originally set up,
# so nothing changes if you don't override anything. Override by exporting
# a variable before running a script, e.g.:
#   RUST_SRC=/path/to/my/rust ./build_crates_batch.sh ...

RUST_SRC="${RUST_SRC:-$HOME/rust}"
TARGET_TRIPLE="${TARGET_TRIPLE:-$(rustc -vV | sed -n 's/^host: //p')}"

STAGE1="${STAGE1:-$RUST_SRC/build/$TARGET_TRIPLE/stage1/bin/rustc}"
LLVM_PROFDATA="${LLVM_PROFDATA:-$RUST_SRC/build/$TARGET_TRIPLE/ci-llvm/bin/llvm-profdata}"
LLVM_COV="${LLVM_COV:-$RUST_SRC/build/$TARGET_TRIPLE/ci-llvm/bin/llvm-cov}"

# cargo names this directory after a hash that changes with the registry
# protocol, not the crate. Picking whichever one is actually there avoids
# hardcoding it.
REGISTRY="${REGISTRY:-$(ls -d "$HOME"/.cargo/registry/src/*/ 2>/dev/null | head -1)}"

COVERAGE_OUT="${COVERAGE_OUT:-$HOME/coverage-results}"
WORKDIR="${WORKDIR:-$HOME/coverage-work}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER_COV="${FILTER_COV:-$SCRIPT_DIR/filter_cov.py}"

# The instrumented driver's filename includes a build hash that changes
# every time stage1 gets rebuilt, so it has to be found, not hardcoded.
# The instrumented one is the biggest .so in the directory, since coverage
# counters add real size to it.
find_driver() {
    ls -S "$RUST_SRC/build/$TARGET_TRIPLE/stage1-rustc/$TARGET_TRIPLE/release/deps"/librustc_driver-*.so 2>/dev/null | head -1
}

require_stage1() {
    if [ ! -x "$STAGE1" ]; then
        echo "ERROR: no instrumented stage1 rustc at $STAGE1" >&2
        echo "  build one first: RUSTFLAGS_BOOTSTRAP=\"-Cinstrument-coverage\" python3 x.py build library --stage 1" >&2
        exit 1
    fi
}
