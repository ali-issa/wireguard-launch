# Security

## Reporting a vulnerability

Please report security issues **privately** via GitHub's
[private vulnerability reporting](https://github.com/ali-issa/wireguard-launch/security/advisories/new)
(the *Security* tab → *Report a vulnerability*). Do not open a public issue for
anything exploitable. I'll acknowledge and work a fix as quickly as I can.

## What's in scope

This project provisions a server, so the interesting surface is what it installs:
the WireGuard server, the `wg-manage` CLI, and the optional web portal.

## Design notes (so you know what to expect)

- **No secrets in this repo.** Server keys, the basic-auth password, the TLS
  certificate, and the nginx↔app proxy token are all generated *on the instance*
  at first boot. Nothing sensitive is committed, so the script is safe to host
  publicly.
- **The web portal is privilege-separated.** It runs as the unprivileged
  `wgportal` user, bound to `127.0.0.1`, behind nginx (TLS + HTTP basic auth +
  rate limiting + fail2ban). The only thing it may run as root is
  `/usr/local/sbin/wg-portal-helper`, a thin wrapper that whitelists a handful of
  verbs and re-validates the client name. The app never touches `/etc/wireguard`
  directly.
- **CSRF**: state-changing requests require a double-submit cookie (`SameSite=Lax`,
  `Secure`, `HttpOnly`) plus a same-origin check; the proxy token ensures the app
  only answers requests that came through nginx.

## Operator responsibilities

- **TLS is self-signed by default** (an IP can't get a public CA cert), so
  browsers warn once. For a trusted cert, point a domain at the server and use
  Let's Encrypt. Treat the warning as expected only on your own server.
- **Lock down exposure.** Open only the ports you need in the Lightsail firewall.
  For the strongest posture, make the portal reachable **only over the VPN** (see
  the README) or close TCP 443 and manage clients via the CLI over SSH.
- **Keep it patched.** `unattended-upgrades` is enabled for automatic security
  updates; reboot periodically so kernel updates take effect.
- **Rotate** the portal password (`htpasswd /etc/wg-portal/htpasswd admin`) and
  revoke unused clients (`wg-manage remove <name>`).
