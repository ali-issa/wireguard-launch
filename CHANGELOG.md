# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-06-22

### Added
- Self-contained Debian/Lightsail launch script (`lightsail-launch.sh`) that
  provisions a WireGuard server on first boot: auto-detected public IP and WAN
  interface, correct two-way NAT, IP forwarding, and `unattended-upgrades` +
  `fail2ban`.
- `wg-manage` CLI — add/remove/list/show/qr clients with file-locked, collision-
  free IP allocation that reuses freed addresses; non-disruptive live updates.
- Optional hardened web portal: HTTPS (self-signed) + HTTP basic auth via nginx,
  generate / download / QR / revoke clients, privilege-separated behind a narrow
  `sudo` helper.
- `bootstrap.sh` — tiny user-data stub that fetches and runs the full script,
  working around Lightsail's 16 KB launch-script limit.
- `build.sh` to assemble the bundle from `src/` (reproducible, base64-embedded).
- Test suite (`tests/`) and GitHub Actions CI; `Makefile`, `LICENSE` (MIT),
  `SECURITY.md`, `CONTRIBUTING.md`, `.editorconfig`, and `uninstall.sh`.

### Fixed
- Portal returned HTTP 500 after login because `/etc/wg-portal` (0750) wasn't
  traversable by nginx's `www-data`; the directory is now 0755 while the secret
  files inside stay 0640.
- "Bad CSRF token" when adding a client: replaced a brittle process-global token
  with a stateless double-submit cookie, relaxed `Referrer-Policy` to
  `same-origin` (so browsers send a real `Origin`), and made the same-origin
  check tolerate `Origin: null`.

[Unreleased]: https://github.com/ali-issa/wireguard-launch/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ali-issa/wireguard-launch/releases/tag/v0.1.0
