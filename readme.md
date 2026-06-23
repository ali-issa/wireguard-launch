# wireguard-launch

[![ci](https://github.com/ali-issa/wireguard-launch/actions/workflows/ci.yml/badge.svg)](https://github.com/ali-issa/wireguard-launch/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A turnkey, self-contained **launch script** that turns a fresh Debian box
(AWS Lightsail, EC2, or any VPS) into a hardened WireGuard VPN server — with a
client-management CLI and an optional web portal for generating, downloading,
and revoking client configs (with QR codes).

Copy one script to a fresh instance and run it — done. (See the
[quick start](#quick-start--aws-lightsail); Lightsail's *Launch script* box has a
16 KB limit, so the full script is copied up and run rather than pasted there.)

---

## What you get

- **WireGuard server**, fully configured on first boot.
  - Auto-detects the **public IP** (IMDSv2 → IMDSv1 → external lookup) and the
    **WAN interface** at runtime — no hardcoded `ens5`, no hardcoded IP.
  - Correct NAT: forward rules in *both* directions + masquerade, re-derived on
    every interface start so it survives NIC renames.
- **`wg-manage` CLI** to add / remove / list clients.
  - File-locked, collision-free IP allocation that **reuses freed addresses**
    (the original guide grep-parsed the config and could clash).
  - Live changes via `wg set` (existing peers stay connected); the on-disk
    config is regenerated from a `clients/` source-of-truth.
- **Optional web portal** (`ENABLE_PORTAL=true`, on by default):
  - HTTPS (self-signed) + HTTP basic auth via **nginx**.
  - Create a client, **download its `.conf`**, show a **scannable QR**, revoke.
  - Runs as an unprivileged user with a **narrow `sudo`** rule to a single
    validated helper — the web app never runs as root or touches keys directly.
  - CSRF protection, same-origin checks, rate limiting, and a proxy-token so the
    app only answers requests that came through nginx.
- **Baseline hardening**: `unattended-upgrades` for automatic security patches,
  and `fail2ban` jails for SSH and the portal's basic auth.
- **Idempotent**: safe to re-run; everything logs to `/var/log/wg-launch.log`.

---

## Quick start — AWS Lightsail

> **Heads-up:** Lightsail caps the *Launch script* box at **16 KB**, and
> `lightsail-launch.sh` is larger — pasting it there fails with
> *"user data launch script exceeds the 16 KB limit"*. So **don't** paste the
> full script into that box. Use **Method A** below (copy it up and run it), or
> **Method B** (paste the tiny `bootstrap.sh` stub instead).

1. **Create an instance** → *Linux/Unix* → *OS Only* → **Debian** (12+). Leave
   the *Launch script* box empty (unless using Method B).
2. (Recommended) Attach a **static IP** so your endpoint doesn't change on
   stop/start.
3. Open ports in the **Lightsail firewall** (Networking tab — this is separate
   from the instance):

   | Protocol | Port  | Why            |
   |----------|-------|----------------|
   | UDP      | 51820 | WireGuard      |
   | TCP      | 443   | Web portal     |
   | TCP      | 22    | SSH (default)  |

### Method A — copy the script up and run it (simplest)

Debian Lightsail's default SSH user is `admin`; the key is the one you download
from the Lightsail console (*Account → SSH keys*). Run from your machine, in this
repo's directory:

```bash
# replace <region> (e.g. eu-west-2) and <INSTANCE_IP> with yours
scp -i ~/.ssh/LightsailDefaultKey-<region>.pem \
    lightsail-launch.sh admin@<INSTANCE_IP>:/tmp/

ssh -i ~/.ssh/LightsailDefaultKey-<region>.pem \
    admin@<INSTANCE_IP> 'sudo bash /tmp/lightsail-launch.sh'
```

To change defaults, pass them inline (note `sudo VAR=… bash …`):

```bash
ssh -i ~/.ssh/LightsailDefaultKey-<region>.pem admin@<INSTANCE_IP> \
    'sudo ENABLE_PORTAL=false WG_LISTEN_PORT=51820 bash /tmp/lightsail-launch.sh'
```

### Method B — auto-run on first boot (bootstrap stub)

Host `lightsail-launch.sh` somewhere reachable (it contains **no secrets** — keys
and passwords are generated on the instance), set `SCRIPT_URL` in
[`bootstrap.sh`](bootstrap.sh), and paste that ~1.6 KB stub into the Lightsail
*Launch script* box. It downloads and runs the full script on first boot.

### After it finishes (~2 minutes)

- **Web portal**: browse to `https://<INSTANCE_IP>/`, accept the self-signed cert
  warning, and log in as `admin`. Get the generated password with:

  ```bash
  ssh -i ~/.ssh/LightsailDefaultKey-<region>.pem admin@<INSTANCE_IP> \
      'sudo cat /root/wg-portal-credentials.txt'
  ```

- **CLI**: SSH in and run `sudo wg-manage add my-phone`.

## Provision everything with OpenTofu (optional)

Prefer infrastructure-as-code? The [`opentofu/`](opentofu/) module creates the
Lightsail instance, a **static IP**, and the **firewall ports** (the manual
console step), booting `bootstrap.sh` as user-data:

```bash
cd opentofu
cp terraform.tfvars.example terraform.tfvars   # set region, SSH key, allowed IPs
tofu init && tofu apply
```

It runs on your machine (no extra load on the 512 MB box). See
[`opentofu/README.md`](opentofu/README.md) for inputs and how to adopt an
existing instance via `tofu import`.

## Quick start — any existing Debian server

Copy the script to the server and run it as root:

```bash
scp lightsail-launch.sh user@server:/tmp/
ssh user@server 'sudo bash /tmp/lightsail-launch.sh'
```

---

## Configuration

Override defaults by exporting environment variables before running (when
running by hand use `sudo -E` so they pass through):

| Variable          | Default      | Meaning                                            |
|-------------------|--------------|----------------------------------------------------|
| `ENABLE_PORTAL`   | `true`       | Install the web portal (`false` = CLI only)        |
| `PORTAL_USER`     | `admin`      | Portal basic-auth username                          |
| `WG_LISTEN_PORT`  | `51820`      | WireGuard UDP port                                 |
| `WG_SUBNET`       | `10.0.0`     | Client `/24` base (server is `.1`)                 |
| `WG_DNS`          | `1.1.1.1`    | DNS pushed to clients                              |
| `WG_ALLOWED_IPS`  | `0.0.0.0/0`  | `0.0.0.0/0` = full tunnel; narrow it for split DNS |
| `WG_ENDPOINT_HOST`| `auto`       | `auto` = detect public IP; or set a domain/IP      |
| `WG_KEEPALIVE`    | `25`         | `PersistentKeepalive` seconds                      |

Example — CLI only, custom port, split tunnel to a private subnet:

```bash
sudo -E env ENABLE_PORTAL=false WG_LISTEN_PORT=53 WG_ALLOWED_IPS=10.0.0.0/24 \
  bash lightsail-launch.sh
```

If you change settings later, edit `/etc/wireguard/wg-manage.conf` and run
`sudo wg-manage rebuild-conf` (existing clients keep their keys/IPs).

---

## Managing clients (CLI)

```bash
sudo wg-manage add mom-phone     # create + print config and a scannable QR
sudo wg-manage list              # name, IP, created, (use 'wg show' for handshakes)
sudo wg-manage show mom-phone    # print the .conf again
sudo wg-manage qr   mom-phone    # reprint the QR in the terminal
sudo wg-manage remove mom-phone  # revoke (live + persisted), frees the IP
```

Each client lives in `/etc/wireguard/clients/<name>/` (its keys, assigned IP,
and `.conf`). Adding/removing is non-disruptive to other connected peers.

---

## The web portal

Browse to `https://<server-ip>/`, authenticate, and you can:

- **Add a client** — type a name, get a page with a QR code + a `.conf` download.
- **View / download** any client's config.
- **Revoke** a client (disconnects the device and frees its address).

### Security model

The portal is a sensitive surface (it mints VPN credentials), so it's locked
down in depth:

- **TLS + basic auth at nginx.** The cert is self-signed against the server IP,
  so browsers show a one-time warning — expected for an IP-only endpoint. For a
  trusted cert, point a domain at the server and use Let's Encrypt.
- **No root in the web app.** It runs as the system user `wgportal`, bound to
  `127.0.0.1`. The only privileged thing it can do is
  `sudo /usr/local/sbin/wg-portal-helper`, which whitelists a handful of verbs
  and re-validates the client name before calling `wg-manage`.
- **Proxy token.** nginx injects a secret header; the app rejects anything
  without it, so it can't be driven by other local processes.
- **CSRF + same-origin checks** on every state-changing request; **rate
  limiting** in nginx; **fail2ban** bans repeated auth failures.

### Make the portal reachable only over the VPN (most secure)

Once you've issued your first client, you can stop exposing the portal to the
internet and require being on the VPN to reach it. Edit
`/etc/nginx/sites-available/wg-portal`, bind the HTTPS server to the WireGuard
address, and drop the public HTTP redirect:

```nginx
# was: listen 443 ssl default_server;  (and the [::]:443 line)
listen 10.0.0.1:443 ssl;
```

Then `sudo nginx -t && sudo systemctl reload nginx`. Now `https://10.0.0.1/`
works only while connected to the VPN. (You can also just close TCP 443 in the
Lightsail firewall and manage clients via the CLI over SSH.)

---

## Files on the server

```
/usr/local/sbin/wg-manage              client management CLI
/usr/local/sbin/wg-portal-helper       privileged shim (sudo target for the portal)
/etc/wireguard/wg0.conf                server interface (regenerated by wg-manage)
/etc/wireguard/wg-manage.conf          settings (subnet, DNS, endpoint, ...)
/etc/wireguard/wg-nat.sh               PostUp/PostDown NAT helper
/etc/wireguard/clients/<name>/         per-client keys, ip, and .conf
/opt/wg-portal/portal.py               the web app (stdlib only)
/etc/nginx/sites-available/wg-portal   TLS + basic-auth vhost
/etc/wg-portal/htpasswd|proxy-token    portal secrets
/root/wg-portal-credentials.txt        generated admin login (chmod 600)
/var/log/wg-launch.log                 provisioning log
```

---

## Uninstall

Remove everything the script installed — services, the portal, and **all** client
configs/keys (apt packages are left in place):

```bash
scp uninstall.sh admin@<INSTANCE_IP>:/tmp/
ssh admin@<INSTANCE_IP> 'sudo bash /tmp/uninstall.sh'   # add --yes to skip the prompt
```

---

## Troubleshooting

- **Can't connect from a client.** Confirm UDP `51820` is open in the *Lightsail*
  firewall (not just the host). Check the server: `sudo wg show`.
- **Portal unreachable.** `sudo systemctl status nginx wg-portal`,
  `sudo nginx -t`, and check TCP `443` is open in the Lightsail firewall.
- **No internet through the tunnel.** `sysctl net.ipv4.ip_forward` should be `1`;
  `sudo iptables -t nat -L POSTROUTING -n` should show a MASQUERADE rule.
- **Public IP changed** (instance stopped without a static IP). Client configs
  embed the endpoint detected at creation time; reissue clients, or set
  `WG_ENDPOINT_HOST` to a stable domain. Attaching a static IP avoids this.
- **Full provisioning log:** `sudo cat /var/log/wg-launch.log`.

---

## Development

The deployable `lightsail-launch.sh` is **generated** — don't edit it by hand.
Edit the canonical sources in [`src/`](src/), then rebuild and test:

```bash
make build        # assemble src/* into lightsail-launch.sh (or: ./build.sh)
make test         # lint + build-drift + wg-manage + portal tests (tests/run.sh)
```

CI runs the same suite on every push. The build is reproducible, so `make test`
fails if `lightsail-launch.sh` is stale — commit it alongside any `src/` edit.

| Source                         | Installed as                              |
|--------------------------------|-------------------------------------------|
| `src/install.sh.tmpl`          | the orchestration body of the launch script |
| `src/wg-manage`                | `/usr/local/sbin/wg-manage`               |
| `src/wg-portal-helper`         | `/usr/local/sbin/wg-portal-helper`        |
| `src/wg-nat.sh`                | `/etc/wireguard/wg-nat.sh`                |
| `src/portal.py`                | `/opt/wg-portal/portal.py`                |
| `src/nginx-wg-portal.conf`     | `/etc/nginx/sites-available/wg-portal`    |
| `src/wg-portal.service`        | `/etc/systemd/system/wg-portal.service`   |
| `src/fail2ban-wg.local`        | `/etc/fail2ban/jail.d/wg-portal.local`    |

`build.sh` base64-embeds each source into the single launch script (so arbitrary
content survives without quoting issues). The original manual walkthrough this
project automates is preserved in [`docs/manual-setup.md`](docs/manual-setup.md).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md): edit `src/`, run `make build` and
`make test`, and commit the regenerated bundle.

## Security

Keys and passwords are generated on the instance, never stored in this repo. The
portal is privilege-separated and fronted by nginx (TLS + basic auth). To report
a vulnerability or read the full security model, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © Ali Issa
