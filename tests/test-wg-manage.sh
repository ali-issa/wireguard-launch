#!/usr/bin/env bash
# Exercise wg-manage against a mocked environment: IP allocation + reuse,
# config regeneration, and input validation. No root or real WireGuard needed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
rc=0
ok(){ echo "  ok   $*"; }
fail(){ echo "  FAIL $*"; rc=1; }

mkdir -p "$TMP/bin" "$TMP/wgroot/clients"
echo SERVER_PRIV > "$TMP/wgroot/server_private.key"
echo SERVER_PUB  > "$TMP/wgroot/server_public.key"
cat > "$TMP/wgroot/wg-manage.conf" <<CONF
WG_INTERFACE=wg0
WG_SUBNET=10.0.0
WG_SERVER_IP=10.0.0.1
WG_LISTEN_PORT=51820
WG_DNS=1.1.1.1
WG_ALLOWED_IPS=0.0.0.0/0
WG_KEEPALIVE=25
WG_ENDPOINT_HOST=auto
CONF

# stub external tools
cat > "$TMP/bin/wg" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  genkey) echo "PRIV$RANDOM$RANDOM";;
  pubkey) read -r k; echo "PUBKEYof_${k}";;
  show)   [ "${3:-}" = "dump" ] && printf 'SP\tSPUB\t51820\toff\n'; exit 0;;
  set)    exit 0;;
esac
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/qrencode"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/flock"
printf '#!/usr/bin/env bash\necho 203.0.113.45\n' > "$TMP/bin/curl"
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"

# point a copy of wg-manage at the temp tree and neuter the root check
sed -e "s|/etc/wireguard/wg-manage.conf|$TMP/wgroot/wg-manage.conf|" \
    -e "s|WG_DIR=\"/etc/wireguard\"|WG_DIR=\"$TMP/wgroot\"|" \
    -e "s|require_root() {.*}|require_root() { :; }|" \
    "$ROOT/src/wg-manage" > "$TMP/wg-manage"
chmod +x "$TMP/wg-manage"
W="$TMP/wg-manage"
ipof(){ cat "$TMP/wgroot/clients/$1/ip" 2>/dev/null; }

"$W" add alice >/dev/null 2>&1 || fail "add alice errored"
"$W" add bob   >/dev/null 2>&1 || fail "add bob errored"
"$W" add carol >/dev/null 2>&1 || fail "add carol errored"
[ "$(ipof alice)" = 10.0.0.2 ] && ok "alice -> .2"  || fail "alice ip=$(ipof alice)"
[ "$(ipof bob)"   = 10.0.0.3 ] && ok "bob -> .3"    || fail "bob ip=$(ipof bob)"
[ "$(ipof carol)" = 10.0.0.4 ] && ok "carol -> .4"  || fail "carol ip=$(ipof carol)"

"$W" remove bob >/dev/null 2>&1 || fail "remove bob errored"
[ -d "$TMP/wgroot/clients/bob" ] && fail "bob dir remains" || ok "bob removed"

"$W" add dave >/dev/null 2>&1 || fail "add dave errored"
[ "$(ipof dave)" = 10.0.0.3 ] && ok "dave reused freed .3" || fail "dave ip=$(ipof dave) (expected 10.0.0.3)"

conf="$TMP/wgroot/wg0.conf"
if grep -q "# alice" "$conf" && grep -q "# carol" "$conf" && grep -q "# dave" "$conf"; then
  ok "wg0.conf lists alice/carol/dave"; else fail "wg0.conf missing peers"; fi
grep -q "# bob" "$conf" && fail "wg0.conf still lists bob" || ok "wg0.conf excludes bob"
grep -q "Endpoint = 203.0.113.45:51820" "$TMP/wgroot/clients/dave/dave.conf" \
  && ok "client conf has detected endpoint" || fail "client endpoint wrong"

"$W" add alice >/dev/null 2>&1 && fail "duplicate name allowed" || ok "duplicate rejected"
"$W" add "bad name" >/dev/null 2>&1 && fail "invalid name allowed" || ok "invalid name rejected"

exit $rc
