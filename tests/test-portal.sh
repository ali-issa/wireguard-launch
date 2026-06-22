#!/usr/bin/env bash
# Drive the real portal process over HTTP with a mocked privileged helper:
# proxy-token guard, listing, downloads, and the double-submit cookie CSRF.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
PORT="${PORTAL_TEST_PORT:-8091}"
rc=0
ok(){ echo "  ok   $*"; }
fail(){ echo "  FAIL $*"; rc=1; }
code(){ curl -s -o /dev/null -w '%{http_code}' "$@"; }

mkdir -p "$TMP/bin"
TOKEN="testproxytoken"; echo "$TOKEN" > "$TMP/proxy-token"

# fake sudo emulates: sudo -n /usr/local/sbin/wg-portal-helper <verb> [name]
cat > "$TMP/bin/sudo" <<'EOF'
#!/usr/bin/env bash
verb="${3:-}"; name="${4:-}"
case "$verb" in
  clients) printf 'alice\t10.0.0.2\t2026-01-01T00:00:00Z\tPUBALICE\n';;
  wgdump)  printf 'srv\tspub\t51820\toff\n'
           printf 'PUBALICE\tpsk\t1.2.3.4:5\t10.0.0.2/32\t%s\t1\t2\toff\n' "$(date +%s)";;
  getconf) printf '[Interface]\n# %s\n' "$name";;
  qrpng)   printf 'PNGDATA';;
  add|remove) exit 0;;
  *) echo forbidden >&2; exit 2;;
esac
EOF
chmod +x "$TMP/bin/sudo"
export PATH="$TMP/bin:$PATH"

PORTAL_BIND=127.0.0.1 PORTAL_PORT="$PORT" PORTAL_TOKEN_FILE="$TMP/proxy-token" \
  python3 "$ROOT/src/portal.py" &
PID=$!
trap 'kill "$PID" 2>/dev/null; rm -rf "$TMP"' EXIT

for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done

B="http://127.0.0.1:$PORT"
H=(-H "X-Portal-Token: $TOKEN")
jar="$TMP/jar"

[ "$(code "$B/")" = 403 ] && ok "no proxy token -> 403" || fail "proxy-token guard"

c=$(curl -s "${H[@]}" -c "$jar" -o "$TMP/idx" -w '%{http_code}' "$B/")
[ "$c" = 200 ] && ok "GET / -> 200" || fail "GET / = $c"
grep -q alice "$TMP/idx" && ok "client listed" || fail "client not listed"
grep -q wgcsrf "$jar" && ok "csrf cookie set" || fail "csrf cookie not set"
csrf=$(grep -oE "name=csrf value='[^']+'" "$TMP/idx" | head -1 | sed "s/.*value='//;s/'//")
[ -n "$csrf" ] && ok "csrf field rendered" || fail "no csrf field"

curl -s "${H[@]}" -D - -o /dev/null "$B/client/alice/config" \
  | grep -qi 'content-disposition: attachment' && ok "config download is attachment" || fail "config disposition"
curl -s "${H[@]}" -D - -o /dev/null "$B/client/alice/qr.png" \
  | grep -qi 'content-type: image/png' && ok "qr is image/png" || fail "qr content-type"

[ "$(code "${H[@]}" -X POST "$B/add" --data "csrf=$csrf&name=zz")" = 403 ] \
  && ok "POST without cookie -> 403" || fail "csrf no-cookie"
[ "$(code "${H[@]}" -b "$jar" -X POST "$B/add" --data "csrf=$csrf&name=zz")" = 303 ] \
  && ok "POST cookie+field -> 303" || fail "csrf valid"
[ "$(code "${H[@]}" -b "$jar" -X POST "$B/add" --data "csrf=WRONG&name=zz")" = 403 ] \
  && ok "POST mismatched field -> 403" || fail "csrf mismatch"
[ "$(code "${H[@]}" -b "$jar" -H 'Origin: https://evil.com' -X POST "$B/add" --data "csrf=$csrf&name=zz")" = 403 ] \
  && ok "cross-origin POST -> 403" || fail "origin check"
[ "$(code "${H[@]}" -o /dev/null "$B/client/ghost")" = 404 ] \
  && ok "unknown client -> 404" || fail "404 handling"

exit $rc
