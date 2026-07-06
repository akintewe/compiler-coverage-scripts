# Compiler Coverage Scripts

Scripts for finding gaps in Rust compiler test coverage -- functions the test suite never calls but real crates do.

## The pipeline

There are 4 steps in order:

1. **Collect compiler coverage** -- run the test suite with an instrumented rustc, get a baseline JSON of what functions the tests hit
2. **Collect crate coverage** -- compile real crates with the same instrumented rustc, get a JSON of what functions each crate triggers
3. **Triage** -- compare the two JSONs to find functions hit by crates but not the test suite (gaps)
4. **Minimize** -- take a gap and shrink the crate to the smallest code that still triggers it

---

## Step 1: Collect compiler coverage (baseline)

Build an instrumented stage1 and run all test suites:

    python3 x.py run compiler-coverage --stage 1

This runs ui, ui-fulldeps, run-make, run-make-cargo, incremental, and crashes test suites.
Writes a merged coverage JSON to:

    /var/tmp/jackh726_akintewe_codecoverage/compiler_ui_coverage/fresh-coverage-july1.json

Only needs to be done once unless the compiler changes.

---

## Step 2: Collect crate coverage

Build a batch of crates with the instrumented rustc:

    ./build_crates_batch.sh <output-subfolder> <crate1> <crate2> ...

Example:

    ./build_crates_batch.sh new_crates regex smallvec itertools indexmap

Coverage JSONs are written to:

    /var/tmp/jackh726_akintewe_codecoverage/<output-subfolder>/<crate>/coverage.json

---

## Step 3: Triage (find gaps)

Compare a crate coverage JSON against the baseline:

    python3 diff_coverage.py <crate-coverage.json> <suite-coverage.json>

Example:

    python3 diff_coverage.py \
      /var/tmp/jackh726_akintewe_codecoverage/new_crates/itertools/coverage.json \
      /var/tmp/jackh726_akintewe_codecoverage/compiler_ui_coverage/fresh-coverage-july1.json

Prints functions hit by the crate but not the test suite.

To run on multiple crates at once:

    for crate in regex smallvec itertools indexmap; do
      echo "=== $crate ==="
      python3 diff_coverage.py \
        /var/tmp/jackh726_akintewe_codecoverage/new_crates/${crate}/coverage.json \
        /var/tmp/jackh726_akintewe_codecoverage/compiler_ui_coverage/fresh-coverage-july1.json
    done

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
4. verifies the panic does NOT fire on the test suite
5. runs cargo-minimize to shrink the crate
6. restores the compiler automatically on exit

Minimized results are saved to the crate copy directory.

---

## Outputs

All outputs are in the shared folder:

    /var/tmp/jackh726_akintewe_codecoverage/
      compiler_ui_coverage/   -- baseline coverage JSON (143,734 functions, all 6 test suites)
      top10_crates/           -- top 10 crates
      outside_top10/          -- serde, serde_derive, regex-syntax, thiserror, log, once_cell, memchr
      uncommon_crates/        -- phantom_newtype, siderust, statig
      new_crates/             -- regex, smallvec, itertools, indexmap
      minimizations/          -- minimized test cases
