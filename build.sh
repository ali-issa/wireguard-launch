#!/usr/bin/env bash
#
# build.sh — assemble the deployable launch script (lightsail-launch.sh) from the
# template + the canonical sources in src/. Each src file is base64-embedded so
# arbitrary content (Python, nginx '$' vars, etc.) survives without quoting games.
#
set -euo pipefail
cd "$(dirname "$0")"

TMPL="src/install.sh.tmpl"
OUT="lightsail-launch.sh"
MARKER="#__EMBEDS__"

# emit_block <srcfile> <destpath> <mode>
# prints shell that recreates <srcfile> at <destpath> on the target.
emit_block() {
  local src="$1" dest="$2" mode="$3" tag
  tag="B64_$(printf '%s' "$dest" | tr -c 'A-Za-z0-9' '_')"
  printf 'mkdir -p "$(dirname %s)"\n' "$dest"
  printf 'base64 -d > "%s" <<'\''%s'\''\n' "$dest" "$tag"
  base64 < "$src"
  printf '%s\n' "$tag"
  printf 'chmod %s "%s"\n\n' "$mode" "$dest"
}

build_embeds() {
  emit_block src/wg-manage            /usr/local/sbin/wg-manage             0755
  emit_block src/wg-portal-helper     /usr/local/sbin/wg-portal-helper      0755
  emit_block src/wg-nat.sh            /etc/wireguard/wg-nat.sh              0755
  emit_block src/portal.py            /opt/wg-portal/portal.py             0755
  emit_block src/nginx-wg-portal.conf /etc/nginx/sites-available/wg-portal  0644
  emit_block src/wg-portal.service    /etc/systemd/system/wg-portal.service 0644
  emit_block src/fail2ban-wg.local    /etc/fail2ban/jail.d/wg-portal.local  0644
}

grep -qF "$MARKER" "$TMPL" || { echo "build: marker '$MARKER' not found in $TMPL" >&2; exit 1; }

{
  sed "/${MARKER}/q" "$TMPL" | sed '$d'   # template up to (not incl.) the marker
  build_embeds                            # the generated embed blocks
  sed "1,/${MARKER}/d" "$TMPL"            # template after the marker
} > "$OUT"

chmod +x "$OUT"
echo "built $OUT ($(wc -l < "$OUT" | tr -d ' ') lines, $(wc -c < "$OUT" | tr -d ' ') bytes)"
