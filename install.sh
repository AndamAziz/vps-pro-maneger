#!/usr/bin/env bash
set -euo pipefail

DOMAIN=""
EMAIL=""
DO_SSL=1
INSTALL_V2RAY=1
STATE_DIR="/etc/vps-pro-maneger"
V2RAY_CFG="/usr/local/etc/v2ray/config.json"
NGINX_SITE="/etc/nginx/sites-enabled/v2ray.kurdcloud.xyz"

usage() {
  echo "Usage: sudo bash install.sh --domain example.com [--email you@x.com] [--no-ssl] [--no-v2ray]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2;;
    --email) EMAIL="$2"; shift 2;;
    --no-ssl) DO_SSL=0; shift;;
    --no-v2ray) INSTALL_V2RAY=0; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -n "$DOMAIN" ]] || { echo "Missing --domain"; exit 1; }

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing packages..."
apt-get update -y
apt-get install -y ca-certificates curl git jq nginx ufw certbot python3-certbot-nginx netcat-openbsd

echo "==> UFW..."
ufw --force enable >/dev/null 2>&1 || true
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow 80/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true

if [[ "$INSTALL_V2RAY" == "1" ]]; then
  if ! command -v /usr/local/bin/v2ray >/dev/null 2>&1; then
    echo "==> Installing v2ray..."
    bash <(curl -fsSL https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
  fi
fi

echo "==> Preparing UUID..."
mkdir -p "$STATE_DIR"
UUID_FILE="$STATE_DIR/uuid"
if [[ -f "$UUID_FILE" ]]; then
  UUID="$(cat "$UUID_FILE")"
else
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  echo "$UUID" > "$UUID_FILE"
fi

# unlock config if immutable
if command -v chattr >/dev/null 2>&1 && [[ -f "$V2RAY_CFG" ]]; then
  chattr -i "$V2RAY_CFG" 2>/dev/null || true
fi

echo "==> Writing v2ray config..."
mkdir -p "$(dirname "$V2RAY_CFG")" /var/log/v2ray
cat >"$V2RAY_CFG" <<CFG
{
  "log": { "loglevel": "warning", "access": "/var/log/v2ray/access.log", "error": "/var/log/v2ray/error.log" },
  "inbounds": [
    { "tag":"vless_443","listen":"127.0.0.1","port":10001,"protocol":"vless",
      "settings":{"clients":[{"id":"$UUID","email":"user@$DOMAIN"}],"decryption":"none"},
      "streamSettings":{"network":"ws","wsSettings":{"path":"/vless"}}},

    { "tag":"vmess_443","listen":"127.0.0.1","port":10000,"protocol":"vmess",
      "settings":{"clients":[{"id":"$UUID","alterId":0,"email":"user@$DOMAIN"}]},
      "streamSettings":{"network":"ws","wsSettings":{"path":"/vmess"}}},

    { "tag":"trojan_443","listen":"127.0.0.1","port":10002,"protocol":"trojan",
      "settings":{"clients":[{"password":"$UUID","email":"user@$DOMAIN"}]},
      "streamSettings":{"network":"ws","wsSettings":{"path":"/trojan"}}},

    { "tag":"vless_80","listen":"127.0.0.1","port":10003,"protocol":"vless",
      "settings":{"clients":[{"id":"$UUID","email":"user@$DOMAIN"}],"decryption":"none"},
      "streamSettings":{"network":"ws","wsSettings":{"path":"/vless80"}}},

    { "tag":"vmess_80","listen":"127.0.0.1","port":10004,"protocol":"vmess",
      "settings":{"clients":[{"id":"$UUID","alterId":0,"email":"user@$DOMAIN"}]},
      "streamSettings":{"network":"ws","wsSettings":{"path":"/vmess80"}}},

    { "tag":"trojan_80","listen":"127.0.0.1","port":10005,"protocol":"trojan",
      "settings":{"clients":[{"password":"$UUID","email":"user@$DOMAIN"}]},
      "streamSettings":{"network":"ws","wsSettings":{"path":"/trojan80"}}}
  ],
  "outbounds": [ { "protocol":"freedom","settings":{} } ]
}
CFG

touch /var/log/v2ray/access.log /var/log/v2ray/error.log

echo "==> Restarting v2ray..."
systemctl daemon-reload
systemctl enable v2ray >/dev/null 2>&1 || true
systemctl restart v2ray
systemctl is-active --quiet v2ray || { journalctl -u v2ray -n 50 --no-pager; exit 1; }

echo "==> Temporary HTTP vhost for certbot..."
cat >"$NGINX_SITE" <<NG
server { listen 80; server_name $DOMAIN;
  location /.well-known/acme-challenge/ { allow all; }
  location / { return 200 "OK\n"; }
}
NG
nginx -t && systemctl restart nginx

if [[ "$DO_SSL" == "1" ]]; then
  echo "==> SSL cert..."
  if [[ -n "$EMAIL" ]]; then
    certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos --non-interactive --redirect || true
  else
    certbot --nginx -d "$DOMAIN" --agree-tos --register-unsafely-without-email --non-interactive --redirect || true
  fi
fi

echo "==> Writing final nginx vhost..."
cat >"$NGINX_SITE" <<NG2
server {
  listen 80;
  server_name $DOMAIN;

  location /.well-known/acme-challenge/ { allow all; }

  location /vless80  { proxy_pass http://127.0.0.1:10003; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location /vmess80  { proxy_pass http://127.0.0.1:10004; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location /trojan80 { proxy_pass http://127.0.0.1:10005; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_read_timeout 86400; }

  location / { return 301 https://\$host\$request_uri; }
}

server {
  listen 443 ssl;
  server_name $DOMAIN;

  ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

  location /vless  { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location /vmess  { proxy_pass http://127.0.0.1:10000; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location /trojan { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_read_timeout 86400; }

  location / { return 200 "OK\n"; }
}
NG2

nginx -t && systemctl restart nginx

echo "✅ Done. UUID: $UUID"
