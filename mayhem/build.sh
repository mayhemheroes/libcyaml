#!/usr/bin/env bash
#
# mayhem/build.sh — build libcyaml's fuzz targets + the upstream unit-test suite.
#
#   build/fuzz_load                  sanitized + libFuzzer -> target `fuzz_load` (in-process
#                                    cyaml_load_data/save_data harness over the planner schema)
#   build/fuzz_planner               sanitized + libFuzzer -> target `planner` (in-process
#                                    harness over the planner example CLI's exact code path:
#                                    cyaml_load_file -> use -> cyaml_save_file via the example's
#                                    own main(), input staged to a /tmp file)
#   build/fuzz_load-standalone       standalone run-once reproducer for fuzz_load
#   build/fuzz_planner-standalone    standalone run-once reproducer for planner
#   build/release/planner            sanitized + DWARF-3   -> the upstream planner example CLI
#                                    itself (local repro artifact for `planner` findings)
#   build/debug/test/units/cyaml-*   NORMAL flags          -> upstream ttest unit suite, run by
#                                    mayhem/test.sh (never compiled there)
#
# libcyaml is a plain-Makefile C library over libyaml (apt libyaml-dev, baked into the image).
# The sanitized build uses VARIANT=release with $SANITIZER_FLAGS/$DEBUG_FLAGS appended via the
# environment (the Makefile uses `CFLAGS +=`, so env flags combine with upstream's own flags).
# The whole sanitized build (library AND harnesses) also carries SanitizerCoverage
# ($FUZZER_COV_FLAGS = -fsanitize=fuzzer-no-link) so libFuzzer/Mayhem edge coverage counts the
# LIBRARY's edges, not just the harness TU's — without it the fuzz_load run measured 5 edges.
# The test suite is a separate, clean VARIANT=debug build tree — upstream's normal flags.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# `=` (not `:=`) on purpose: an explicit empty value is honored (no sancov), matching the
# SANITIZER_FLAGS off-switch semantics for a fully natural build.
: "${FUZZER_COV_FLAGS=-fsanitize=fuzzer-no-link}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS FUZZER_COV_FLAGS DEBUG_FLAGS CC LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}"

FUZZ_CFLAGS="$SANITIZER_FLAGS $FUZZER_COV_FLAGS $DEBUG_FLAGS"

# 1) Sanitized + sancov-instrumented library and planner example
#    (VARIANT=release: upstream's -O2; extra flags via env — Makefile uses `CFLAGS +=`).
env CFLAGS="$FUZZ_CFLAGS" LDFLAGS="$FUZZ_CFLAGS" \
    make -j"$MAYHEM_JOBS" VARIANT=release CC="$CC" examples

# 2) In-process libFuzzer harnesses (fuzzer + standalone reproducer each), linked against the
#    sanitized+instrumented static library so the fuzzed LIBRARY code is instrumented.
# shellcheck disable=SC2086
$CC $FUZZ_CFLAGS $LIB_FUZZING_ENGINE -I include \
    mayhem/fuzz_load.c build/release/libcyaml.a -lyaml -o build/fuzz_load
# shellcheck disable=SC2086
$CC $FUZZ_CFLAGS $LIB_FUZZING_ENGINE -I include \
    mayhem/fuzz_planner.c build/release/libcyaml.a -lyaml -o build/fuzz_planner
# shellcheck disable=SC2086
$CC $FUZZ_CFLAGS "$STANDALONE_FUZZ_MAIN" -I include \
    mayhem/fuzz_load.c build/release/libcyaml.a -lyaml -o build/fuzz_load-standalone
# shellcheck disable=SC2086
$CC $FUZZ_CFLAGS "$STANDALONE_FUZZ_MAIN" -I include \
    mayhem/fuzz_planner.c build/release/libcyaml.a -lyaml -o build/fuzz_planner-standalone

# 3) Upstream unit-test suite (ttest), NORMAL flags, clean VARIANT=debug tree — test.sh only RUNS it.
env CFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" \
    make -j"$MAYHEM_JOBS" VARIANT=debug CC="$CC" \
        build/debug/test/units/cyaml-static build/debug/test/units/cyaml-shared

echo "build.sh: built build/fuzz_load, build/fuzz_planner (+standalones), build/release/planner, and the debug test suite"
