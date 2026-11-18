#!/usr/bin/env bash
# Run the whole workspace test suite (suica/jxl unit tests + suica/jxl_tests)
# on the native and wasm-gc targets, saving raw output per target.
#
# Usage: scripts/run_tests.sh <output-dir> [extra `moon test` args...]
#   e.g. scripts/run_tests.sh out/run1
#        scripts/run_tests.sh out/conf -p suica/jxl_tests/conformance
#
# Writes <output-dir>/{native,wasm-gc}.log (raw `moon test -v` output),
# <output-dir>/{native,wasm-gc}.{passed,failed}.txt (one test name per line)
# and <output-dir>/summary.txt.
#
# Environment:
#   TARGETS                      targets to run (default: "native wasm-gc")
#   MOON_TEST_FLAGS              flags for `moon test` (default: "--release")
#   TEST_TIMEOUT                 per-target timeout for `timeout(1)` (default: 6h)
#   JXL_TESTS_REQUIRE_FIXTURES   default 1 here: missing fixtures fail instead of skip
#                                (run scripts/fetch_fixtures.sh first)
#   JXL_OXIDE_CONFORMANCE_TESTCASES, JXL_OXIDE_DECODE_TESTCASES, JXL_FIXTURES_CACHE:
#                                override fixture locations (see tests/harness/paths.mbt)
set -uo pipefail

if [ $# -lt 1 ]; then
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
OUT="$1"
shift
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

export JXL_TESTS_REQUIRE_FIXTURES="${JXL_TESTS_REQUIRE_FIXTURES:-1}"
TARGETS="${TARGETS:-native wasm-gc}"
FLAGS="${MOON_TEST_FLAGS:---release}"
TIMEOUT="${TEST_TIMEOUT:-6h}"

: > "$OUT/summary.txt"
status=0
for t in $TARGETS; do
  log="$OUT/$t.log"
  echo "== moon test --target $t $FLAGS -v $* ==" | tee -a "$OUT/summary.txt"
  start=$(date +%s)
  # shellcheck disable=SC2086
  (cd "$ROOT" && timeout "$TIMEOUT" moon test --target "$t" $FLAGS -v "$@") > "$log" 2>&1
  rc=$?
  end=$(date +%s)
  # lines look like: [suica/jxl_tests] test conformance/x_test.mbt:12 ("conformance/bike") ok
  grep -E '^\[[^]]+\] test .*\) ok$' "$log" | sed -E 's/^\[([^]]+)\] test [^ ]+ \("(.*)"\) ok$/\1 \2/' > "$OUT/$t.passed.txt"
  grep -E '^\[[^]]+\] test .*\) failed' "$log" | sed -E 's/^\[([^]]+)\] test [^ ]+ \("(.*)"\) failed.*$/\1 \2/' > "$OUT/$t.failed.txt"
  {
    echo "exit code: $rc$([ $rc -eq 124 ] && echo ' (timeout)'), $((end - start))s"
    echo "passed: $(wc -l < "$OUT/$t.passed.txt"), failed: $(wc -l < "$OUT/$t.failed.txt")"
    tail -n 1 "$log"
    echo
  } | tee -a "$OUT/summary.txt"
  [ $rc -ne 0 ] && status=1
done
exit $status
