# Compiler Coverage Scripts

Scripts for finding gaps in Rust compiler test coverage: functions the test suite never calls but real crates do.

## Requirements

- A rust-lang/rust checkout with an instrumented stage1 build (see step 1 below)
- [rustfilt](https://github.com/luser/rustfilt), install with `cargo install rustfilt`
- [cargo-minimize](https://github.com/langston-barrett/cargo-minimize), only needed for step 4

## Setup

All the paths in these scripts (where your rust checkout lives, where output goes, etc.)
come from `env.sh`, with defaults that assume a fairly standard layout. If your setup is
different, override before running anything, e.g.:

    export RUST_SRC=/path/to/your/rust

## The pipeline

There are 4 steps in order:

1. **Collect compiler coverage**: run the test suite with an instrumented rustc, get a baseline JSON of what functions the tests hit
2. **Collect crate coverage**: compile real crates with the same instrumented rustc, get a JSON of what functions each crate triggers
3. **Triage**: compare the two JSONs to find functions hit by crates but not the test suite (gaps)
4. **Minimize**: take a gap and shrink the crate to the smallest code that still triggers it

---

## Step 1: Collect compiler coverage (baseline)

Build an instrumented stage1 and run all test suites:

    python3 x.py run compiler-coverage --stage 1

This runs ui, ui-fulldeps, run-make, run-make-cargo, incremental, and crashes test suites.
Writes a merged coverage JSON to:

    $COVERAGE_OUT/compiler_ui_coverage/fresh-coverage-july1.json

Only needs to be done once unless the compiler changes. If you only have a `.profdata`
file and need to turn it into the same kind of JSON yourself (this is what the step
above does internally), use `export_suite_coverage.sh <profdata> <output.json>`.

---

## Step 2: Collect crate coverage

Build a batch of crates with the instrumented rustc:

    ./build_crates_batch.sh <output-subfolder> <crate1> <crate2> ...

Example:

    ./build_crates_batch.sh new_crates regex smallvec itertools indexmap

Coverage JSONs are written to:

    $COVERAGE_OUT/<output-subfolder>/<crate>/coverage.json

`build_top10_coverage.sh` is the same thing pre-filled with the crates in
`top10_crates.txt`. `build_crate_coverage.sh` does one crate directly from a local
directory instead of the registry cache, if you're testing against crate source
you already have checked out.

---

## Step 3: Triage (find gaps)

Compare a crate coverage JSON against the baseline:

    python3 diff_coverage.py <crate-coverage.json> <suite-coverage.json>

Example:

    python3 diff_coverage.py \
      $COVERAGE_OUT/new_crates/itertools/coverage.json \
      $COVERAGE_OUT/compiler_ui_coverage/fresh-coverage-july1.json

Prints functions hit by the crate but not the test suite.

To run on multiple crates at once:

    for crate in regex smallvec itertools indexmap; do
      echo "=== $crate ==="
      python3 diff_coverage.py \
        $COVERAGE_OUT/new_crates/${crate}/coverage.json \
        $COVERAGE_OUT/compiler_ui_coverage/fresh-coverage-july1.json
    done

`coverage_pipeline.sh` chains steps 2 and 3 together for a list of crates in one shot.

---

## Step 4: Minimize a gap

Take a gap (a function that's uncovered in the test suite) and shrink the crate
to the smallest code that still triggers it:

    ./minimize_gap.sh <crate-dir> <function-file> <function-line> <panic-message>

Example:

    ./minimize_gap.sh \
      ~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/log-0.4.33 \
      compiler/rustc_codegen_llvm/src/debuginfo/metadata/type_map.rs \
      254 \
      "coverage check: build_type_with_children"

The script:
1. inserts a panic into the target function using add_panic.py
2. rebuilds stage1 with the panicking function
3. verifies the panic fires when compiling the crate
4. verifies the panic does NOT fire on the test suite baseline
5. runs cargo-minimize to shrink the crate
6. restores the compiler automatically on exit

Refuses to run if the target compiler file already has uncommitted changes, since
it can't tell those apart from its own edit once both are in the file.

Minimized results are saved to the crate copy directory.

`add_panic.py` finds a function's opening brace by tracking parens/braces, which
covers the normal case but can misfire on something like a multi-line closure body.
For those, `add_panic_closure.py <file> <line> <old-text> <new-text>` does an exact
text swap on one line instead, give it the literal old and new source.

---

## Outputs

All outputs are in `$COVERAGE_OUT` (see `env.sh`), organized into subfolders per run:

    compiler_ui_coverage/   baseline coverage JSON (all 6 test suites)
    top10_crates/           top 10 crates
    new_crates/             whatever you pass to build_crates_batch.sh
    pipeline_results/       output of coverage_pipeline.sh
    minimizations/          minimized test cases
