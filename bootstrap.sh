#!/usr/bin/env bash
#
# bootstrap.sh — tiny Lightsail user-data stub (well under the 16 KB limit).
#
# Lightsail caps the "Launch script" at 16 KB, and lightsail-launch.sh is larger,
# so paste THIS into the launch-script box instead. It downloads and runs the
# full script on first boot. lightsail-launch.sh contains no secrets (all keys
# and passwords are generated on the instance), so a public URL is fine.
#
#   1. Host lightsail-launch.sh somewhere reachable (GitHub raw, a release
#      asset, a gist, or S3) and put the URL below.
#   2. Paste this file into the Lightsail "Launch script" box.
#
set -euo pipefail

# ---- EDIT THIS ----
SCRIPT_URL="https://raw.githubusercontent.com/USER/REPO/main/lightsail-launch.sh"
# -------------------

# Optional: override installer defaults (these pass through to lightsail-launch.sh)
# export ENABLE_PORTAL=true
# export PORTAL_USER=admin
# export WG_LISTEN_PORT=51820
# export WG_ENDPOINT_HOST=auto

mkdir -p /var/log
exec > >(tee -a /var/log/wg-bootstrap.log) 2>&1
echo "[bootstrap] starting"

# curl is preinstalled on Lightsail Debian, but make sure.
command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl; }

tmp="$(mktemp /tmp/lightsail-launch.XXXXXX.sh)"
for i in 1 2 3 4 5; do
  if curl -fsSL "$SCRIPT_URL" -o "$tmp" && [ -s "$tmp" ]; then
    echo "[bootstrap] downloaded $(wc -c < "$tmp") bytes"
    break
  fi
  echo "[bootstrap] download attempt ${i} failed; retrying in 10s..."
  sleep 10
done
[ -s "$tmp" ] || { echo "[bootstrap] ERROR: could not download ${SCRIPT_URL}" >&2; exit 1; }

bash "$tmp"
