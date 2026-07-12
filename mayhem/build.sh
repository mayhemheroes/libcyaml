#!/usr/bin/env bash
#
# mayhem/build.sh — build libcyaml's fuzz targets + the upstream unit-test suite.
#
#   build/release/planner            sanitized + DWARF-3   -> target `planner` (file-input YAML
#                                    load/save example CLI, the fork's original target)
#   build/fuzz_load                  sanitized + libFuzzer -> target `fuzz_load` (in-process
#                                    cyaml_load_data/save_data harness over the planner schema)
#   build/fuzz_load-standalone       standalone run-once reproducer for fuzz_load
#   build/debug/test/units/cyaml-*   NORMAL flags          -> upstream ttest unit suite, run by
#                                    mayhem/test.sh (never compiled there)
#
# libcyaml is a plain-Makefile C library over libyaml (apt libyaml-dev, baked into the image).
# The sanitized build uses VARIANT=release with $SANITIZER_FLAGS/$DEBUG_FLAGS appended via the
# environment (the Makefile uses `CFLAGS +=`, so env flags combine with upstream's own flags).
# The test suite is a separate, clean VARIANT=debug build tree — upstream's normal flags.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}"

# 1) Sanitized library + planner example (VARIANT=release: upstream's -O2; sanitizers via env).
env CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" LDFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
    make -j"$MAYHEM_JOBS" VARIANT=release CC="$CC" examples

# 2) In-process libFuzzer harness over the same planner schema (fuzzer + standalone reproducer),
#    linked against the sanitized static library so the fuzzed code is instrumented.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE -I include \
    mayhem/fuzz_load.c build/release/libcyaml.a -lyaml -o build/fuzz_load
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" -I include \
    mayhem/fuzz_load.c build/release/libcyaml.a -lyaml -o build/fuzz_load-standalone

# 3) Upstream unit-test suite (ttest), NORMAL flags, clean VARIANT=debug tree — test.sh only RUNS it.
env CFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" \
    make -j"$MAYHEM_JOBS" VARIANT=debug CC="$CC" \
        build/debug/test/units/cyaml-static build/debug/test/units/cyaml-shared

echo "build.sh: built build/release/planner, build/fuzz_load(+standalone), and the debug test suite"
