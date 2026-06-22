#!/usr/bin/env bash
# Syntax-check every shell script and the Python portal.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rc=0

shells="src/wg-manage src/wg-portal-helper src/wg-nat.sh src/install.sh.tmpl
        build.sh bootstrap.sh lightsail-launch.sh uninstall.sh
        tests/run.sh tests/test-lint.sh tests/test-build.sh
        tests/test-wg-manage.sh tests/test-portal.sh"

for f in $shells; do
  [ -f "$f" ] || continue
  if bash -n "$f" 2>/tmp/_lint.$$; then echo "  ok   bash -n $f"
  else echo "  FAIL bash -n $f"; cat "/tmp/_lint.$$"; rc=1; fi
done
rm -f "/tmp/_lint.$$"

if python3 -m py_compile src/portal.py 2>/tmp/_py.$$; then echo "  ok   py_compile src/portal.py"
else echo "  FAIL py_compile src/portal.py"; cat "/tmp/_py.$$"; rc=1; fi
rm -rf src/__pycache__ "/tmp/_py.$$"

if command -v shellcheck >/dev/null 2>&1; then
  for f in src/wg-manage src/wg-portal-helper src/wg-nat.sh build.sh bootstrap.sh; do
    [ -f "$f" ] || continue
    if shellcheck -S error -x "$f"; then echo "  ok   shellcheck $f"
    else echo "  FAIL shellcheck $f"; rc=1; fi
  done
else
  echo "  --   shellcheck not installed; skipping (runs in CI)"
fi

exit $rc
