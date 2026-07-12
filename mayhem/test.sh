#!/usr/bin/env bash
#
# mayhem/test.sh — RUN libcyaml's full upstream unit-test suite (tlsa ttest framework).
# mayhem/build.sh already built the two upstream test runners with normal flags
# (build/debug/test/units/cyaml-static and cyaml-shared — the exact binaries `make test`
# runs, covering utf8/util/free/load/errs/file/save/copy). This script only RUNS them,
# from the repo root (the file tests read test/data/*.yaml relative to cwd), and parses
# each runner's ttest summary line:  "<PASS|FAIL>: <passed> of <total> tests passed."
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "${SRC:-/mayhem}"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}"
  local tests=$(( passed + failed + skipped ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": 0,
      "skipped": $skipped,
      "other": 0
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":0,"skipped":%d,"other":0}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$skipped"
  [ "$failed" -eq 0 ]
}

passed=0 failed=0 skipped=0

run_suite() {
  local bin="$1"
  if [ ! -x "$bin" ]; then
    echo "test.sh: $bin missing — build.sh must build it (not rebuilding here)" >&2
    failed=$(( failed + 1 ))
    return
  fi
  local out rc summary p t todo
  out="$(LD_LIBRARY_PATH=build/debug "$bin" -q 2>&1)"; rc=$?
  echo "== $bin =="; echo "$out" | tail -5
  # ttest summary: "PASS: <p> of <t> tests passed." (+ optional "TODO: <n> tests unimplemented.")
  summary="$(grep -E '^(PASS|FAIL): [0-9]+ of [0-9]+ tests passed\.' <<<"$out" | tail -1)"
  if [ -z "$summary" ]; then
    echo "test.sh: no ttest summary from $bin (rc=$rc) — treating as failure" >&2
    failed=$(( failed + 1 ))
    return
  fi
  p="$(sed -E 's/^(PASS|FAIL): ([0-9]+) of ([0-9]+) tests passed\./\2/' <<<"$summary")"
  t="$(sed -E 's/^(PASS|FAIL): ([0-9]+) of ([0-9]+) tests passed\./\3/' <<<"$summary")"
  todo="$(grep -oE '^TODO: [0-9]+ test' <<<"$out" | grep -oE '[0-9]+' || true)"
  passed=$(( passed + p ))
  failed=$(( failed + t - p ))
  skipped=$(( skipped + ${todo:-0} ))
  # exit code must agree with the summary — a crashing runner is a failure even if it printed PASS
  if [ "$rc" -ne 0 ] && [ "$t" -eq "$p" ]; then
    echo "test.sh: $bin printed PASS but exited $rc — counting as a failure" >&2
    failed=$(( failed + 1 ))
  fi
}

run_suite build/debug/test/units/cyaml-static
run_suite build/debug/test/units/cyaml-shared

echo "test.sh: passed=$passed failed=$failed skipped=$skipped"
emit_ctrf tlsa-ttest "$passed" "$failed" "$skipped"
