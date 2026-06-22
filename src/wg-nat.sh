#!/usr/bin/env bash
#
# wg-nat.sh up|down <wg-iface> — add/remove NAT + forwarding rules so VPN
# clients can reach the internet. Called from wg0.conf PostUp/PostDown.
#
# The WAN interface is detected at runtime from the default route, so this keeps
# working if the NIC is renamed (e.g. ens5 -> enp0s5) — unlike a hardcoded name.
#
set -euo pipefail

action="${1:?usage: wg-nat.sh up|down <wg-iface>}"
wg_if="${2:-wg0}"

wan_if="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')"
[ -n "$wan_if" ] || { echo "wg-nat: no default route found" >&2; exit 1; }

case "$action" in
  up)
    iptables -A FORWARD -i "$wg_if" -o "$wan_if" -j ACCEPT
    iptables -A FORWARD -i "$wan_if" -o "$wg_if" -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -t nat -A POSTROUTING -o "$wan_if" -j MASQUERADE
    ;;
  down)
    iptables -D FORWARD -i "$wg_if" -o "$wan_if" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$wan_if" -o "$wg_if" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -t nat -D POSTROUTING -o "$wan_if" -j MASQUERADE 2>/dev/null || true
    ;;
  *)
    echo "wg-nat: unknown action '$action'" >&2; exit 1
    ;;
esac
