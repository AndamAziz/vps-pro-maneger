# 🚀 KurdCloud VPS Manager Pro

All-in-one VPS manager for Debian / Ubuntu, installed with **one command**:
**Xray** (VLESS · VMess · Trojan · Shadowsocks over WebSocket on 443 *and* 80, VLESS-Reality), **Hysteria 2**, **WireGuard**, **OpenVPN (UDP + TCP)**, **SSH over WebSocket (HTTP 101)**, **SSH tunnel accounts + UDPGW**, **Squid**, SSL, firewall, Fail2ban, backup and a **Telegram admin bot**.

- [Install](#-install-one-line) · [Ports](#-ports-after-a-full-install) · [Protocols](#-protocols-how-each-one-works) · [CLI](#-cli-reference) · [Troubleshooting](#-troubleshooting) · [Kurdish / کوردی](#-کوردی--ڕێنمایی-تەواو)

## ⚡ Install (one line)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/install.sh)
```

This installs the manager and opens the menu (`vpsmanager`).

**Everything, unattended** (tuning + Fail2ban + Xray WS 443/80 + Reality + Hysteria 2 + WireGuard + OpenVPN UDP/TCP + Squid + UDPGW + SSH-WS + firewall, then prints your links):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/install.sh) --full --user myuser --domain vpn.example.com
```

| Installer option | Meaning |
|---|---|
| `--full` | install and harden everything, unattended |
| `--user NAME` | first user (default `admin`) |
| `--domain D` | domain for TLS (A record must already point at the server; without it port 443 uses a self-signed certificate) |
| `--quick [NAME]` | same as `--full` with the first user NAME |
| `--no-menu` | install only, do not open the menu |
| `--branch B` | install from another branch |

The run is **idempotent**: a failing step is reported, the rest continues, and you can simply run it again (or `vpsmanager full-setup myuser vpn.example.com`) after fixing the cause. Re-running never changes working configuration.

**Requirements:** root, systemd, Debian 10+ / Ubuntu 20.04+ (x86_64 or arm64), outbound access to github.com (the installer checks DNS/HTTPS first and fails loudly).

Update at any time: `vpsmanager update` (also applies new features to an existing install).

## 🔌 Ports after a full install

| Port | Service | Notes |
|---|---|---|
| TCP **22** | SSH | your normal SSH port (auto-detected, never locked out by ufw) |
| TCP **80** | Xray WS (no SSL) **+ SSH over WebSocket** | |
| TCP **443** | Xray WS (SSL) **+ SSH over WebSocket (SSL)** | |
| TCP **8443** | VLESS + Reality + Vision | no domain/certificate needed |
| UDP **443** | Hysteria 2 | QUIC |
| UDP **51820** | WireGuard | |
| UDP **1194** + TCP **1194** | OpenVPN (both protocols at once) | |
| TCP **8080** | Squid HTTP/HTTPS proxy | open, no username/password |
| 7300 (local only) | BadVPN UDPGW | for SSH apps (UDP / calls / games) |

Check what is really open any time: `vpsmanager ports`. Cloud providers may have an **extra firewall in their panel** – open the same ports there too.

## 🧩 Protocols: how each one works

### Xray — VLESS / VMess / Trojan / Shadowsocks over WebSocket (443 SSL + 80)
One inbound pair serves all four protocols on both ports, separated by URL path (VLESS fallbacks to loopback WebSocket inbounds): `/<id>-vless`, `/<id>-vmess`, `/<id>-trojan`, `/<id>-ss`.

- `vpsmanager user show NAME --qr` prints every link with QR codes (443 *and* 80 variants, Reality, Hysteria 2).
- The Xray config is generated from the user database and validated with `xray run -test` before every restart (rolled back on error).
- Bundled: BitTorrent + private-IP blocking.
- `vpsmanager xray test` checks every path on 443 and 80 and tells you what is wrong.
- Reality (`xray add reality 8443 "" www.microsoft.com`) needs no domain.

### SSH over WebSocket (HTTP `101 Switching Protocols`)
For tunnel apps (HTTP Custom, HTTP Injector, NapsternetV …) that send an HTTP payload and expect `101`. It runs behind Xray as the **default fallback** of ports 80 and 443, so the proxy paths above keep working.

```
GET / HTTP/1.1[crlf]Host: your.domain[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]
```

- Any Host / path is accepted – change the Host in the payload freely, no server change needed.
- App settings: server = your domain/IP, port **80** (or **443** with TLS/SNI), SSH user/password from `vpsmanager ssh add NAME DAYS 'password'`.
- A normal browser request (no `Upgrade`) gets a harmless `200` page; `CONNECT` gets `200 Connection established`.
- Raw payload tunnel: WebSocket *frames* (e.g. `websocat`) are not supported.
- `vpsmanager ssh ws test` → `✔ port 80: 101 Switching Protocols + SSH banner`.

### OpenVPN — UDP and TCP together
Two instances share one PKI (easy-rsa 3, ECDSA, tls-crypt, AES-256-GCM): UDP `server` (10.8.0.0/24) and TCP `server-tcp` (10.9.0.0/24), both on port 1194.

`vpsmanager ovpn add NAME` creates three profiles in `/etc/vps-manager/openvpn/`:

| File | Use |
|---|---|
| `NAME.ovpn` | UDP **and** TCP; tries UDP first, falls back to TCP |
| `NAME-udp.ovpn` | UDP only |
| `NAME-tcp.ovpn` | TCP only |

Existing UDP-only (or TCP-only) installs are migrated: `vpsmanager ovpn add-tcp [port]` / `add-udp [port]` (also done by `full-setup`); existing client profiles are regenerated. `vpsmanager ovpn del NAME` revokes a client.

Get a profile to your device: `scp root@IP:/etc/vps-manager/openvpn/NAME*.ovpn .` (or the Telegram bot `/ovpn NAME`). Profiles contain a private key – do not share them.

### WireGuard
`vpsmanager wg add phone` prints the config + QR. The endpoint port and server key are read from the **live interface** (`wg show`), so it also works when the port was changed later. `vpsmanager wg debug 60` explains a failing handshake (key mismatch, firewall, damaged packets).

### Hysteria 2
QUIC/UDP with user/password auth (the same users as Xray), optional Salamander obfuscation, ACME or self-signed certificate. `vpsmanager hy2 install [port] [domain|-]`.

### Squid (HTTP/HTTPS proxy)
**No username / password.** Abuse protection built in: private/loopback destinations blocked, no mail/NetBIOS/telnet ports, max 80 connections per client address.

An open proxy on the internet is scanned within minutes. **Restrict it to your own IP(s)** to stop the flood:

```bash
vpsmanager squid ip 203.0.113.0/24      # only these IPs/ranges (ufw follows)
vpsmanager squid ip open                # open to everyone again
```

Other commands: `squid install [port]`, `squid restart`, `squid port N`, `squid test`.

### SSH, tunnel accounts, UDPGW
Change/add SSH port, root and password-login toggles, public keys, **expiring tunnel accounts** with max simultaneous logins, BadVPN UDPGW, SSH-WS (above).

## 🛡️ System & security

- BBR, kernel/limit tuning, conntrack table sizing (`vpsmanager tune`).
- **ufw**: opens SSH (checked with `sshd -T`, lock-out guard), every installed service and the ports that are *really* listening.
- **Fail2ban** for SSH (5 failures → 1 h ban).
- Let's Encrypt (certbot, auto-renew; Xray is stopped/started by hooks) with self-signed fallback.
- Daily account-expiry sweep (systemd timer), backup/restore (`vpsmanager backup`, copy the archive off-server).
- **Telegram admin bot** (`/add /del /renew /links /usage /status /backup /wg /ovpn /ssh`, yt-dlp downloader), admin-only.

## 🖥️ CLI reference

```bash
vpsmanager                              # interactive menu
vpsmanager status                       # server info + service states (incl. OpenVPN UDP/TCP, SSH-WS)
vpsmanager full-setup [user] [domain]   # everything, unattended
vpsmanager update                       # update the manager itself

# users (one account → every installed protocol)
vpsmanager user add alice 30            # 30 days (omit / 0 = unlimited)
vpsmanager user show alice --qr         # links + QR codes
vpsmanager user renew alice 30 | user del alice | user list [--json] | user usage

# Xray
vpsmanager xray add multi-ws 443 example.com 80
vpsmanager xray add reality 8443 "" www.microsoft.com
vpsmanager xray add vless-ws|vmess-ws|trojan|ss2022 <port> [domain] [path]
vpsmanager xray list | del <tag> | install | update | test | loglevel [level]

# other protocols
vpsmanager hy2 install [port] [domain|-]
vpsmanager wg add phone | wg del phone | wg debug [seconds]
vpsmanager ovpn add laptop | ovpn del laptop | ovpn install [udp] [tcp] | ovpn add-udp|add-tcp [port]
vpsmanager ssh add bob 30 'pass' 2      # 30 days, max 2 logins
vpsmanager ssh del bob | ssh list
vpsmanager ssh ws [install [port]|test|remove]
vpsmanager squid install|restart|test|port N|ip <IP…|open>
vpsmanager ssl issue example.com [email] | ssl list | ssl renew

# diagnostics
vpsmanager ports                        # every listening port + public/local
vpsmanager watch 60                     # connect from your phone meanwhile: which ports your traffic reaches, did Xray/WireGuard accept it
vpsmanager diag                         # one-shot report (DNS, Xray, WireGuard, firewall) - paste it when asking for help

# system
vpsmanager tune | fail2ban | backup | restore FILE | expire
```

## 🩺 Troubleshooting

| Symptom | What to run / check |
|---|---|
| a client connects but no data | `vpsmanager watch 60` while connecting: *arrived 0* → blocked before the server (ISP / provider firewall); *Xray accepted 0* → wrong path / host / TLS setting in the app |
| WS links do not work | `vpsmanager xray test`; the app must use exactly the link's path, host/SNI and TLS on/off |
| WireGuard never handshakes | `vpsmanager wg debug 60`, re-import a fresh `wg add` config |
| SSH-WS app fails | `vpsmanager ssh ws test`, `journalctl -u vpsm-sshws -n 30`; payload must contain `Upgrade: websocket`; use an ASCII SSH password |
| OpenVPN fails | `journalctl -u openvpn-server@server -n 30` (UDP) / `-u openvpn-server@server-tcp` (TCP); open 1194 UDP+TCP in the provider panel |
| Squid is hammered / slow | `vpsmanager squid ip <your-IP>` |
| installer: *Could not resolve host* | the VPS DNS is broken; the installer reports it and fixes systemd-resolved when it can |

## 🔒 Notes

- Configuration lives in `/etc/vps-manager` (mode 700); logs in `/var/log/vps-manager`; backups in `/var/backups/vps-manager`.
- Enabling ufw first allows your SSH ports and every service the manager installed.
- WS+TLS and Trojan need a domain (certificate from *SSL*); without one a self-signed cert is used and links carry `allowInsecure=1`.
- Applying user/protocol changes restarts Xray/Hysteria (a few hundred milliseconds of reconnect).
- Links, UUIDs and passwords printed in a terminal or pasted into a chat are exposed – rotate them (`vpsmanager user del` + `user add`).
- Harden after install: restrict Squid to your IP, use SSH keys, set a strong root password.
- Uninstall the manager: `bash /opt/vps-manager-pro/uninstall.sh` (installed services are left in place).

## 🧪 Development

```bash
for t in tests/test_*.sh; do bash "$t"; done     # offline tests: config, full setup, installer sync, update, WireGuard, OpenVPN, SSH-WS
shellcheck -x -S warning install.sh uninstall.sh vpsmanager lib/*.sh
```

CI (GitHub Actions) runs `bash -n`, ShellCheck, all test scripts and flake8 on every push and pull request. Fixes are merged to `main`, so `vpsmanager update` always brings the latest.

---

## 🇮🇶 کوردی — ڕێنمایی تەواو

### دامەزراندن
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/install.sh) --full --user ناو --domain دۆمێنەکەت
```
`--full` هەموو شتێک بە خۆکاری دایدەمەزرێنێت: BBR، Fail2ban، Xray (WebSocket لەسەر 443 بە SSL و 80 بێ SSL)، Reality، Hysteria 2، WireGuard، OpenVPN (UDP و TCP)، Squid، UDPGW، SSH-WS و فایەروال. دەتوانیت دووبارەی بکەیتەوە بێ ئەوەی شتێک تێک بچێت. دوای دامەزراندن بنووسە `vpsmanager` بۆ مێنیو.

بۆ ئەپدەیت: `vpsmanager update`

### پۆرتەکان
| پۆرت | خزمەتگوزاری |
|---|---|
| TCP 80 | Xray WebSocket (بێ SSL) + SSH-WS |
| TCP 443 | Xray WebSocket (SSL) + SSH-WS |
| TCP 8443 | VLESS Reality |
| UDP 443 | Hysteria 2 |
| UDP 51820 | WireGuard |
| UDP و TCP 1194 | OpenVPN (هەردووکیان پێکەوە) |
| TCP 8080 | Squid (بێ یوزەر/پاسوۆرد) |

بزانە چی کراوەیە: `vpsmanager ports`. ئەگەر دابینکەری VPS فایەروالی خۆی هەیە، لەوێش هەمان پۆرتەکان بکەرەوە.

### بەکارهێنەر و لینکەکان
```bash
vpsmanager user add ناو 30        # ٣٠ ڕۆژ (0 = بێ سنوور)
vpsmanager user show ناو --qr     # هەموو لینک و QR
```
یەک هەژمار = هەموو پرۆتۆکۆلەکانی Xray و Hysteria 2.

### SSH بە WebSocket (وەیب سۆکت 101)
بۆ ئەپەکانی HTTP Custom / HTTP Injector و هاوشێوەکانی. Payload:
```
GET / HTTP/1.1[crlf]Host: دۆمێنەکەت[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]
```
- لەسەر پۆرتی **80** (یان **443** بە SSL) کار دەکات.
- Host هەرچییەک بێت وەردەگیرێت؛ بۆ گۆڕینی دۆمێنەکە تەنها Host لە payload بگۆڕە.
- هەژماری SSH: `vpsmanager ssh add ناو 30 'پاسوۆردی-ئینگلیزی'` (پاسوۆرد با ASCII بێت).
- تێست: `vpsmanager ssh ws test`

### OpenVPN — UDP و TCP
```bash
vpsmanager ovpn add mobile
scp root@IP:/etc/vps-manager/openvpn/mobile*.ovpn .
```
سێ فایل دروست دەبێت: `mobile.ovpn` (هەردووکیان، یەکەم UDP دواتر TCP)، `mobile-udp.ovpn` و `mobile-tcp.ovpn`. فایلەکە لە مۆبایل بە **OpenVPN Connect** هاوردە بکە (Import → File). فایلەکە کلیلی تایبەتی تێدایە؛ بڵاوی مەکەرەوە و دوای هاوردەکردن بیسڕەوە.

### WireGuard
```bash
vpsmanager wg add phone           # کۆنفیگ + QR
vpsmanager wg debug 60            # ئەگەر handshake نەکرا
```

### Squid
بێ یوزەر و پاسوۆردە. بۆ ئەوەی سکانەرەکان بەکاری نەهێنن، بۆ IPـی خۆت سنووردار بکە:
```bash
vpsmanager squid ip IPی_خۆت        # تەنها ئەو IP
vpsmanager squid ip open           # بۆ هەموو
```

### ئەگەر کار نەکرد
1. `vpsmanager watch 60` — لە ماوەی ٦٠ چرکەدا لە مۆبایل پەیوەندی بکە. `arrived 0` = پەیوەندییەکە نەگەیشتووەتە سێرڤەر (بلۆکی ئینتەرنێت/فایەروالی دابینکەر).
2. `vpsmanager xray test` بۆ WebSocket و `vpsmanager ssh ws test` بۆ SSH-WS.
3. `vpsmanager diag` — ئەنجامەکەی بنێرە بۆ یارمەتی.

### ئاسایش
- UUID و پاسوۆردەکان دوای نیشاندان لە چات/تێرمینال بگۆڕە.
- Squid بۆ IPـی خۆت سنووردار بکە، SSH key بەکاربهێنە، پاسوۆردی root بگۆڕە.
- `vpsmanager backup` بکە و فایلەکە لە دەرەوەی سێرڤەر هەڵبگرە.

Made with ❤️ by Andam Aziz · MIT License
