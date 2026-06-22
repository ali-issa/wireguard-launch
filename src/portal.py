#!/usr/bin/env python3
"""Minimal WireGuard client portal.

Runs as the unprivileged 'wgportal' user, bound to localhost, behind nginx
(which terminates TLS and enforces HTTP basic auth). Every privileged action
goes through `sudo wg-portal-helper`; this process never touches /etc/wireguard
directly and never runs as root.

Security model:
  * nginx is the only reachable entry point (TLS + basic auth + rate limiting).
  * nginx injects X-Portal-Token; requests without the matching token are
    rejected, so other local users can't drive the app via 127.0.0.1.
  * State-changing requests require a CSRF token and a same-origin check.
"""
import html
import os
import re
import secrets
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote

BIND = os.environ.get("PORTAL_BIND", "127.0.0.1")
PORT = int(os.environ.get("PORTAL_PORT", "8080"))
TOKEN_FILE = os.environ.get("PORTAL_TOKEN_FILE", "/etc/wg-portal/proxy-token")
HELPER = ["sudo", "-n", "/usr/local/sbin/wg-portal-helper"]
NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,32}$")


def _read_token():
    try:
        with open(TOKEN_FILE, "r") as fh:
            return fh.read().strip()
    except OSError:
        return ""


PROXY_TOKEN = _read_token()
CSRF_TOKEN = secrets.token_urlsafe(32)


def helper(verb, name=None, binary=False, timeout=25):
    cmd = list(HELPER) + [verb]
    if name is not None:
        cmd.append(name)
    proc = subprocess.run(cmd, capture_output=True, timeout=timeout)
    if proc.returncode != 0:
        msg = proc.stderr.decode("utf-8", "replace").strip()
        raise RuntimeError(msg or ("%s failed" % verb))
    return proc.stdout if binary else proc.stdout.decode("utf-8", "replace")


def fmt_handshake(epoch):
    try:
        e = int(epoch)
    except (TypeError, ValueError):
        e = 0
    if e <= 0:
        return "never"
    delta = max(0, int(time.time()) - e)
    if delta < 60:
        return "%ds ago" % delta
    if delta < 3600:
        return "%dm ago" % (delta // 60)
    if delta < 86400:
        return "%dh ago" % (delta // 3600)
    return "%dd ago" % (delta // 86400)


def list_clients():
    handshakes = {}
    try:
        for line in helper("wgdump").splitlines()[1:]:
            cols = line.split("\t")
            if len(cols) >= 5:
                handshakes[cols[0]] = cols[4]
    except Exception:
        pass
    clients = []
    for line in helper("clients").splitlines():
        cols = line.split("\t")
        if len(cols) < 4:
            continue
        name, ip, created, pub = cols[0], cols[1], cols[2], cols[3]
        clients.append({
            "name": name,
            "ip": ip,
            "created": created,
            "handshake": fmt_handshake(handshakes.get(pub, "0")),
        })
    clients.sort(key=lambda c: c["name"].lower())
    return clients


PAGE_CSS = """
*{box-sizing:border-box}
body{font-family:system-ui,Segoe UI,Roboto,sans-serif;margin:0;background:#0f172a;color:#e2e8f0}
.wrap{max-width:840px;margin:0 auto;padding:24px}
h1{font-size:20px;margin:0 0 4px}
a{color:#38bdf8}
table{width:100%;border-collapse:collapse;margin-top:8px}
th,td{padding:9px 10px;text-align:left;border-bottom:1px solid #1e293b;font-size:14px;vertical-align:middle}
th{color:#94a3b8;font-weight:600}
.btn{display:inline-block;padding:6px 12px;border-radius:6px;border:1px solid #334155;background:#1e293b;color:#e2e8f0;text-decoration:none;font-size:13px;cursor:pointer}
.btn.primary{background:#0ea5e9;border-color:#0ea5e9;color:#08131f;font-weight:600}
.btn.danger{border-color:#7f1d1d;color:#fca5a5;background:transparent}
form.inline{display:inline}
input[type=text]{padding:8px 10px;border-radius:6px;border:1px solid #334155;background:#0b1220;color:#e2e8f0;font-size:14px}
.card{background:#111c33;border:1px solid #1e293b;border-radius:10px;padding:18px;margin-top:16px}
.muted{color:#94a3b8;font-size:13px}
img.qr{background:#fff;padding:12px;border-radius:8px;max-width:300px;width:100%}
.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
"""


def layout(title, body):
    return (
        "<!doctype html><html><head><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'>"
        "<title>%s</title><style>%s</style></head><body><div class=wrap>%s</div></body></html>"
        % (html.escape(title), PAGE_CSS, body)
    )


def page_index():
    clients = list_clients()
    rows = []
    for c in clients:
        n = html.escape(c["name"])
        rows.append(
            "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td>"
            "<td class=row>"
            "<a class=btn href='/client/%s'>View</a>"
            "<a class=btn href='/client/%s/config'>Config</a>"
            "<form class=inline method=post action='/client/%s/revoke' "
            "onsubmit=\"return confirm('Revoke %s? This disconnects the device.')\">"
            "<input type=hidden name=csrf value='%s'>"
            "<button class='btn danger' type=submit>Revoke</button></form>"
            "</td></tr>"
            % (n, html.escape(c["ip"]), html.escape(c["created"]),
               html.escape(c["handshake"]), n, n, n, n, CSRF_TOKEN)
        )
    table = (
        "<table><tr><th>Name</th><th>IP</th><th>Created (UTC)</th>"
        "<th>Last handshake</th><th></th></tr>%s</table>"
        % ("".join(rows) or "<tr><td colspan=5 class=muted>No clients yet.</td></tr>")
    )
    add = (
        "<div class=card><h1>Add a client</h1>"
        "<form method=post action='/add' class=row>"
        "<input type=hidden name=csrf value='%s'>"
        "<input type=text name=name placeholder='e.g. mom-phone' "
        "pattern='[A-Za-z0-9_-]{1,32}' required autofocus>"
        "<button class='btn primary' type=submit>Create</button></form>"
        "<p class=muted>Letters, numbers, dash, underscore — up to 32 characters.</p></div>"
        % CSRF_TOKEN
    )
    return layout(
        "WireGuard Portal",
        "<h1>WireGuard clients</h1>" + add + "<div class=card>" + table + "</div>",
    )


def page_client(name):
    by_name = {c["name"]: c for c in list_clients()}
    c = by_name.get(name)
    if c is None:
        return None
    n = html.escape(name)
    body = (
        "<p><a href='/'>&larr; All clients</a></p>"
        "<div class=card><h1>%s</h1>"
        "<p class=muted>IP %s &middot; created %s &middot; last handshake %s</p>"
        "<div class=row>"
        "<a class='btn primary' href='/client/%s/config'>Download .conf</a>"
        "<form class=inline method=post action='/client/%s/revoke' "
        "onsubmit=\"return confirm('Revoke %s?')\">"
        "<input type=hidden name=csrf value='%s'>"
        "<button class='btn danger' type=submit>Revoke</button></form>"
        "</div>"
        "<p class=muted>Scan in the WireGuard mobile app:</p>"
        "<img class=qr src='/client/%s/qr.png' alt='QR code for %s'>"
        "</div>"
        % (n, html.escape(c["ip"]), html.escape(c["created"]),
           html.escape(c["handshake"]), n, n, n, CSRF_TOKEN, n, n)
    )
    return layout("WireGuard - " + name, body)


def error_page(message):
    return layout(
        "Error",
        "<div class=card><h1>Something went wrong</h1>"
        "<p class=muted>%s</p><p><a href='/'>&larr; Back</a></p></div>"
        % html.escape(message),
    )


class Handler(BaseHTTPRequestHandler):
    server_version = "wg-portal"

    def log_message(self, *args):
        pass  # nginx already logs access

    def _guard(self):
        if PROXY_TOKEN and self.headers.get("X-Portal-Token", "") != PROXY_TOKEN:
            self._text(403, "Forbidden")
            return False
        return True

    def _send(self, code, body, ctype="text/html; charset=utf-8", extra=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'",
        )
        if extra:
            for k, v in extra.items():
                self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _text(self, code, msg):
        self._send(code, msg, "text/plain; charset=utf-8")

    def _redirect(self, location):
        self.send_response(303)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _name_from(self, match):
        name = unquote(match.group(1))
        return name if NAME_RE.match(name) else None

    def do_GET(self):
        if not self._guard():
            return
        path = self.path.split("?", 1)[0]

        if path == "/":
            self._send(200, page_index())
            return

        m = re.match(r"^/client/([^/]+)$", path)
        if m:
            name = self._name_from(m)
            page = page_client(name) if name else None
            self._send(200, page) if page else self._text(404, "Not found")
            return

        m = re.match(r"^/client/([^/]+)/config$", path)
        if m:
            name = self._name_from(m)
            if not name:
                self._text(404, "Not found")
                return
            try:
                conf = helper("getconf", name)
            except Exception:
                self._text(404, "Not found")
                return
            self._send(200, conf, "text/plain; charset=utf-8",
                       {"Content-Disposition": 'attachment; filename="%s.conf"' % name})
            return

        m = re.match(r"^/client/([^/]+)/qr\.png$", path)
        if m:
            name = self._name_from(m)
            if not name:
                self._text(404, "Not found")
                return
            try:
                png = helper("qrpng", name, binary=True)
            except Exception:
                self._text(404, "Not found")
                return
            self._send(200, png, "image/png")
            return

        self._text(404, "Not found")

    def _read_form(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > 65536:
            return {}
        raw = self.rfile.read(length).decode("utf-8", "replace")
        return parse_qs(raw)

    def _csrf_ok(self, form):
        token = (form.get("csrf", [""]) or [""])[0]
        if not secrets.compare_digest(token, CSRF_TOKEN):
            return False
        origin = self.headers.get("Origin")
        if origin:  # browsers send Origin on form POSTs; enforce same-origin
            host = self.headers.get("Host", "")
            if not origin.endswith("://" + host):
                return False
        return True

    def do_POST(self):
        if not self._guard():
            return
        path = self.path.split("?", 1)[0]
        form = self._read_form()
        if not self._csrf_ok(form):
            self._text(403, "Bad CSRF token")
            return

        if path == "/add":
            name = (form.get("name", [""]) or [""])[0].strip()
            if not NAME_RE.match(name):
                self._send(400, error_page("Invalid client name."))
                return
            try:
                helper("add", name)
            except Exception as exc:
                self._send(400, error_page(str(exc)))
                return
            self._redirect("/client/" + name)
            return

        m = re.match(r"^/client/([^/]+)/revoke$", path)
        if m:
            name = self._name_from(m)
            if not name:
                self._text(400, "Invalid name")
                return
            try:
                helper("remove", name)
            except Exception:
                pass
            self._redirect("/")
            return

        self._text(404, "Not found")


def main():
    httpd = ThreadingHTTPServer((BIND, PORT), Handler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
