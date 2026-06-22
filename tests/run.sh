#!/usr/bin/env bash
# Run the whole test suite. Exit non-zero if any test fails.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
fail=0

for t in test-lint.sh test-build.sh test-wg-manage.sh test-portal.sh; do
  echo "=== $t ==="
  if bash "$ROOT/$t"; then echo "--- PASS $t"; else echo "--- FAIL $t"; fail=1; fi
  echo
done

if [ "$fail" = 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
  exit 1
fi
