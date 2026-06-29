# Compiler Coverage Scripts

Scripts for measuring which parts of the Rust compiler are exercised by the test suite vs real crates.

## Setup

Requires an instrumented stage1 rustc built with -Cinstrument-coverage. Build it with:

    python3 x.py run compiler-coverage --stage 1

This runs all test suites (ui, ui-fulldeps, run-make, run-make-cargo, incremental, crashes)
and writes a merged profdata to build/coverage/combined.profdata.

## Scripts

### export_suite_coverage.sh

Exports a profdata file to a JSON of function hit counts.

    ./export_suite_coverage.sh <profdata> <output.json>

Example:

    ./export_suite_coverage.sh \
      /home/gh-akintewe/rust/build/coverage/combined.profdata \
      /var/tmp/jackh726_akintewe_codecoverage/compiler_ui_coverage/coverage.json

### build_crate_coverage.sh

Builds a single crate with the instrumented rustc and generates a coverage JSON.
The crate directory must already exist — you can find crate sources in
~/.cargo/registry/src/ after cargo has downloaded them.

    ./build_crate_coverage.sh <crate-dir> <output-dir>

Example:

    ./build_crate_coverage.sh \
      ~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/syn-2.0.118 \
      ~/crate-coverage/syn-out

### diff_coverage.py

Compares two coverage JSONs and prints functions hit by the first but not the second.

    python3 diff_coverage.py <crate-coverage.json> <suite-coverage.json>

Example:

    python3 diff_coverage.py \
      ~/crate-coverage/syn-out/coverage.json \
      /var/tmp/jackh726_akintewe_codecoverage/compiler_ui_coverage/coverage.json

### build_top10_coverage.sh

Builds the top 10 most downloaded crates from crates.io using their source from
~/.cargo/registry/src/ and generates coverage JSONs for each.
Outputs go to /var/tmp/jackh726_akintewe_codecoverage/top10_crates/<crate-name>/

    ./build_top10_coverage.sh

## Outputs

All outputs are stored in the shared folder:

    /var/tmp/jackh726_akintewe_codecoverage/
      compiler_ui_coverage/   -- combined test suite profdata and coverage JSON
      either_vs_ui/           -- either crate vs UI tests only (24 gaps found)
      either_vs_all_suites/   -- either crate vs all 6 test suites (0 gaps found)
      top10_crates/           -- top 10 crates coverage vs all 6 test suites
