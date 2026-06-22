# Manual setup (original guide)

This is the original step-by-step guide that `lightsail-launch.sh` automates.
Kept for reference and for anyone who wants to understand each step. For a real
deployment, use the launch script instead — it auto-detects the WAN interface and
public IP, sets up correct NAT, and adds client management + the web portal.

```bash
sudo apt update
sudo apt install wireguard -y
sudo su
cd /etc/wireguard
umask 077
wg genkey | tee server_private.key | wg pubkey > server_public.key
```

```bash
cat server_private.key   # copy this into PrivateKey =
ip -o -4 route show to default | awk '{print $5}'
```

```bash
vi /etc/wireguard/wg0.conf
```

```ini
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <SERVER_PRIVATE_KEY>
# NAT so clients can reach the internet through this server.
# Replace ens5 with your real WAN interface (check with `ip route`)
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens5 -j MASQUERADE
```

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-wireguard.conf
sudo sysctl -p /etc/sysctl.d/99-wireguard.conf
```

```bash
sudo systemctl enable --now wg-quick@wg0
sudo wg show          # verify it's up
systemctl status wg-quick@wg0
```

Then a manual `add-wg-client.sh` script generated each client by grepping
`wg0.conf` for the next free IP. The launch script replaces this with the more
robust `wg-manage` CLI (file-locked allocation that reuses freed IPs, plus
`remove`/`list`/`show`/`qr`).
