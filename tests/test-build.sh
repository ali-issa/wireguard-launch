#!/usr/bin/env bash
# Verify the committed bundle is current, reproducible, and self-consistent.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rc=0

# 1) The build is reproducible and matches the committed bundle (catches a stale
#    lightsail-launch.sh when someone edits src/ but forgets to run ./build.sh).
tmp="$(mktemp)"
OUT="$tmp" bash build.sh >/dev/null 2>&1
if diff -q "$tmp" lightsail-launch.sh >/dev/null; then
  echo "  ok   committed bundle matches a fresh build"
else
  echo "  FAIL committed bundle is stale — run ./build.sh and commit"
  rc=1
fi
rm -f "$tmp"

# 2) Every expected file is embedded.
for tag in B64__usr_local_sbin_wg_manage B64__usr_local_sbin_wg_portal_helper \
           B64__etc_wireguard_wg_nat_sh B64__opt_wg_portal_portal_py \
           B64__etc_nginx_sites_available_wg_portal \
           B64__etc_systemd_system_wg_portal_service \
           B64__etc_fail2ban_jail_d_wg_portal_local; do
  if grep -q "<<'${tag}'" lightsail-launch.sh; then echo "  ok   embedded: $tag"
  else echo "  FAIL missing embed: $tag"; rc=1; fi
done

# 3) The embedded portal.py decodes to valid Python (catches base64 corruption).
out="$(mktemp)"
awk -v t="B64__opt_wg_portal_portal_py" \
  'end_seen{next} matched{if($0==t){end_seen=1;next} print} $0 ~ ("'"'"'" t "'"'"'$"){matched=1}' \
  lightsail-launch.sh | base64 -d > "$out"
if python3 -m py_compile "$out" 2>/dev/null; then echo "  ok   embedded portal.py compiles"
else echo "  FAIL embedded portal.py is corrupt"; rc=1; fi
rm -f "$out" "${out}c"

exit $rc
