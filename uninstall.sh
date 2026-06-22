#!/usr/bin/env bash
#
# uninstall.sh — remove everything wireguard-launch installed on this server.
# Run as root:  sudo bash uninstall.sh   (add --yes to skip the prompt)
#
# This deletes the WireGuard config, ALL client keys/configs, and the portal.
# It does NOT remove apt packages (wireguard, nginx, ...).
#
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)." >&2; exit 1; }

WG_INTERFACE="${WG_INTERFACE:-wg0}"
assume_yes=0
[ "${1:-}" = "--yes" ] && assume_yes=1

cat <<EOF
This will REMOVE:
  - systemd services: wg-quick@${WG_INTERFACE}, wg-portal
  - nginx site: wg-portal
  - /etc/wireguard  (server keys, ${WG_INTERFACE}.conf, and ALL client configs)
  - /opt/wg-portal, /etc/wg-portal, /etc/ssl/wg-portal
  - user 'wgportal', its sudoers rule, the fail2ban jail, sysctl drop-in, CLI tools
It will NOT uninstall apt packages.
EOF

if [ "$assume_yes" -ne 1 ]; then
  printf 'Proceed? [y/N] '
  read -r ans
  case "$ans" in
    y | Y | yes | YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

disable_now() { systemctl disable --now "$1" >/dev/null 2>&1 || true; }
disable_now "wg-quick@${WG_INTERFACE}"
disable_now wg-portal

rm -f /etc/nginx/sites-enabled/wg-portal /etc/nginx/sites-available/wg-portal
if command -v nginx >/dev/null 2>&1 && nginx -t >/dev/null 2>&1; then
  systemctl reload nginx >/dev/null 2>&1 || true
fi

rm -f /usr/local/sbin/wg-manage /usr/local/sbin/wg-portal-helper
rm -f /etc/systemd/system/wg-portal.service
rm -f /etc/sudoers.d/wg-portal
rm -f /etc/fail2ban/jail.d/wg-portal.local
rm -f /etc/sysctl.d/99-wireguard.conf
rm -f /root/wg-portal-credentials.txt
rm -rf /opt/wg-portal /etc/wg-portal /etc/ssl/wg-portal
rm -rf /etc/wireguard

systemctl daemon-reload >/dev/null 2>&1 || true
systemctl restart fail2ban >/dev/null 2>&1 || true
id wgportal >/dev/null 2>&1 && userdel wgportal >/dev/null 2>&1 || true

echo "Removed. apt packages were left installed; to purge them:"
echo "  apt-get remove --purge wireguard wireguard-tools qrencode nginx apache2-utils fail2ban"
