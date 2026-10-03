# Changelog

## 6.0.0
Complete rewrite (replaces the previous 5.x Python/Docker/Kubernetes implementation).

- New modular layout (`lib/*.sh`) with a single `vpsmanager` command (interactive menu **and** CLI).
- One-line installer for any Debian/Ubuntu VPS (`install.sh`), idempotent, also used for updates.
- **Xray-core**: VLESS+Reality+Vision, VLESS-WS, VMess-WS, Trojan, Shadowsocks-2022; config generated from a user database, validated before every restart.
- **Hysteria 2** (QUIC) with userpass auth, optional Salamander obfuscation, automatic ACME.
- **WireGuard** and **OpenVPN** (ECDSA, tls-crypt, AES-256-GCM) with client config + QR generation.
- **SSH** management, expiring tunnel accounts, connection limits, BadVPN UDPGW.
- **Squid** proxy with authentication, **SSL** via Let's Encrypt, BBR, ufw, Fail2ban, backup/restore.
- Unified users: one account → links/QR for every installed protocol, expiry enforced by a systemd timer.
- Telegram bot rewritten (admin-only, uses the CLI, runs in its own venv).
- Offline test-suite and CI (ShellCheck + tests).
- Removed legacy scripts, bundled binaries/videos and the unfinished web-panel stubs.
