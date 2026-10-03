# 🚀 KurdCloud VPS Manager Pro

All-in-one VPS manager for Debian / Ubuntu: **Xray (VLESS-Reality, VLESS, VMess, Trojan, Shadowsocks-2022)**, **Hysteria 2**, **WireGuard**, **OpenVPN**, **SSH tunnel accounts + UDPGW**, **Squid**, SSL, firewall, backup and a **Telegram admin bot** — from one command.

## ⚡ Install (one line)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/install.sh)
```

**Everything, unattended** (tuning + Fail2ban + Xray WS 443/80 + Reality + Hysteria2 + WireGuard + OpenVPN + Squid + UDPGW + firewall, then prints your links):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/install.sh) --full --user myuser --domain vpn.example.com
```

`--domain` is optional (A record must already point at the server; without it port 443 uses a self-signed certificate). The run is idempotent: a failing step is reported and the rest continues, so after fixing the cause you can simply run `vpsmanager full-setup myuser vpn.example.com` again.

Then open the menu any time with `vpsmanager` (or `menu`). Re-running the installer (or *System → Update*) upgrades to the latest version.

**Requirements:** root, systemd, Debian 10+ / Ubuntu 20.04+ (x86_64 or arm64), outbound access to github.com.

## 🧩 What's inside

| Module | Features |
|---|---|
| **Users** | One account → links + QR for every installed protocol, expiry/renew, hourly expiry sweep (systemd timer), per-user traffic |
| **Xray-core** | **All-in-one WebSocket: VLESS + VMess + Trojan + Shadowsocks on port 443 (SSL) *and* port 80 (no SSL)** (separated by path), VLESS+Reality+Vision (no domain needed), VLESS-WS, VMess-WS (TLS optional), Trojan, Shadowsocks-2022; config auto-generated and validated (`xray run -test`) before every restart; BitTorrent + private-IP blocking |
| **Hysteria 2** | QUIC/UDP, userpass auth, Salamander obfuscation, built-in ACME or self-signed |
| **WireGuard** | Server setup, clients with preshared keys, config file + QR, live add/remove |
| **OpenVPN** | easy-rsa 3 (ECDSA), tls-crypt, AES-256-GCM, UDP/TCP, `.ovpn` profiles, revocation |
| **SSH** | Change/add port, root & password-login toggles, keys, expiring tunnel accounts, max-logins, BadVPN UDPGW |
| **Squid** | Open HTTP/HTTPS proxy (no username/password): install, restart, change port, show open ports, self-test, optional IP restriction |
| **SSL** | Let's Encrypt (certbot) with auto-renew hook, self-signed fallback |
| **System** | BBR, kernel tuning, ufw (auto-opens installed ports), Fail2ban, swap, OS update, backup/restore, self-update |
| **Telegram bot** | `/add /del /renew /links /usage /status /backup /wg /ovpn /ssh`, plus yt-dlp video downloader — admin-only |

## 🖥️ CLI (for scripts & automation)

```bash
vpsmanager status
vpsmanager user add alice 30          # 30 days (omit / 0 = unlimited)
vpsmanager user show alice --qr       # links + QR codes
vpsmanager user renew alice 30
vpsmanager user usage
vpsmanager xray add multi-ws 443 example.com 80   # WS on 443 (SSL) + 80 (plain), all 4 protocols
vpsmanager xray add reality 443 "" www.microsoft.com
vpsmanager xray add vless-ws 8443 cdn.example.com /ws
vpsmanager xray add trojan 2053 example.com
vpsmanager xray add ss2022 8388
vpsmanager hy2 install [port] [domain|-]
vpsmanager full-setup myuser vpn.example.com   # everything, unattended
vpsmanager xray test                          # check every WS path on 443 and 80
vpsmanager watch 60                           # connect from your phone meanwhile: which ports your traffic reaches, did Xray/WireGuard accept it
vpsmanager diag                               # one-shot report (DNS, Xray, WireGuard handshakes, firewall) - paste it when asking for help
vpsmanager fail2ban && vpsmanager tune        # SSH brute-force protection, conntrack/limits
vpsmanager wg add phone               # prints config + QR
vpsmanager ovpn add laptop            # → /etc/vps-manager/openvpn/laptop.ovpn
vpsmanager ssh add bob 30 'pass' 2    # SSH account, 30 days, max 2 logins
vpsmanager backup / restore FILE / update
```

## 🔒 Notes

- Configuration lives in `/etc/vps-manager` (mode 700); logs in `/var/log/vps-manager`; backups in `/var/backups/vps-manager`.
- Enabling ufw from the menu first allows your SSH ports and every service the manager installed.
- Reality needs no domain/certificate. WS+TLS and Trojan need a domain (issue a cert from *SSL*), otherwise a self-signed cert is used and the generated links carry `allowInsecure=1`.
- Applying user/protocol changes restarts Xray/Hysteria (a few hundred milliseconds of reconnect).
- Uninstall the manager: `bash /opt/vps-manager-pro/uninstall.sh` (installed services are left in place).

## 🧪 Development

```bash
bash tests/test_config.sh                       # offline tests (bash + jq + openssl)
shellcheck -x -S warning vpsmanager lib/*.sh install.sh
```

CI runs ShellCheck, the offline tests and flake8 on every push.

---

## 🇮🇶 کوردی — دامەزراندن

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/install.sh)
```

دوای دامەزراندن، هەر کاتێک بنووسە `vpsmanager` بۆ کردنەوەی مێنیوەکە. بۆ دامەزراندنی خێرای هەموو شتێک (BBR + Reality + VMess + یەکەم بەکارهێنەر): `--quick ناوی_بەکارهێنەر` زیاد بکە.

Made with ❤️ by Andam Aziz · MIT License
