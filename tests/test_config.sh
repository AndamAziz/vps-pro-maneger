#!/usr/bin/env bash
# Offline tests: user DB, Xray config generation, share links, Hysteria2 config.
# Needs only bash + jq + openssl. Run: bash tests/test_config.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export VPSM_ETC="$TMP/etc" VPSM_LOG_DIR="$TMP/log" VPSM_BACKUP_DIR="$TMP/bak" VPSM_NONINTERACTIVE=1
for f in common users ssl xray hysteria; do . "$ROOT/lib/$f.sh"; done
db_init
setting_set public_ip 203.0.113.7

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

# --- users
user_add alice 30 >/dev/null; user_add bob 0 >/dev/null
check "two users stored"            '[ "$(jq length "$USERS_DB")" = 2 ]'
check "duplicate rejected"          '! user_add alice 1 >/dev/null 2>&1'
check "bad name rejected"           '! user_add "bad name" 1 >/dev/null 2>&1'
user_renew bob 10 >/dev/null
check "renew sets expiry"           '[ "$(jq -r ".[]|select(.name==\"bob\")|.expiry" "$USERS_DB")" -gt 0 ]'
jq 'map(if .name=="bob" then .expiry=1 else . end)' "$USERS_DB" | json_write "$USERS_DB"
check "expired user excluded"       '[ "$(users_active | jq length)" = 1 ]'
user_renew bob 0 >/dev/null
check "unlimited renew"             '[ "$(users_active | jq length)" = 2 ]'

# --- xray inbounds (written directly; the binary is not needed to build)
echo '[]' > "$XRAY_INB"
XRAY_BIN=/bin/true
inb_add '{"tag":"reality-443","type":"reality","port":443,"sni":"www.microsoft.com","privateKey":"PRIV","publicKey":"PUB","shortId":"abcd1234abcd1234"}'
inb_add '{"tag":"vless-ws-8443","type":"vless-ws","port":8443,"host":"","path":"/ws","tls":false,"insecure":false,"cert":"","key":""}'
inb_add '{"tag":"vmess-ws-8080","type":"vmess-ws","port":8080,"host":"example.com","path":"/vm","tls":true,"insecure":true,"cert":"/c.pem","key":"/k.pem"}'
inb_add '{"tag":"trojan-2053","type":"trojan","port":2053,"host":"","tls":true,"insecure":true,"cert":"/c.pem","key":"/k.pem"}'
inb_add '{"tag":"ss2022-8388","type":"ss2022","port":8388,"serverKey":"c2VydmVya2V5MTIzNDU2Nw=="}'
cfg="$(xray_build_config)"
check "config is valid JSON"        'jq -e . <<<"$cfg" >/dev/null'
check "api + 5 proxy inbounds"      '[ "$(jq ".inbounds|length" <<<"$cfg")" = 6 ]'
check "reality has vision flow"     '[ "$(jq -r ".inbounds[]|select(.tag==\"reality-443\")|.settings.clients[0].flow" <<<"$cfg")" = xtls-rprx-vision ]'
check "both users in clients"       '[ "$(jq ".inbounds[]|select(.tag==\"trojan-2053\")|.settings.clients|length" <<<"$cfg")" = 2 ]'
check "ws tls inbound uses certs"   '[ "$(jq -r ".inbounds[]|select(.tag==\"vmess-ws-8080\")|.streamSettings.tlsSettings.certificates[0].certificateFile" <<<"$cfg")" = /c.pem ]'
check "private ranges blocked"      'jq -e ".routing.rules[]|select(.ip==[\"geoip:private\"])" <<<"$cfg" >/dev/null'
check "bittorrent blocked"          'jq -e ".routing.rules[]|select(.protocol==[\"bittorrent\"])" <<<"$cfg" >/dev/null'
jq 'map(.expiry=1)' "$USERS_DB" | json_write "$USERS_DB"
check "no users -> no proxy inbound" '[ "$(xray_build_config | jq ".inbounds|length")" = 1 ]'
jq 'map(.expiry=0)' "$USERS_DB" | json_write "$USERS_DB"

# --- links
links="$(xray_user_links alice)"
check "5 links generated"           '[ "$(wc -l <<<"$links")" = 5 ]'
check "reality link"                'grep -q "^vless://.*@203.0.113.7:443?.*security=reality.*pbk=PUB.*sid=abcd1234abcd1234" <<<"$links"'
check "vmess link decodes"          'grep "^vmess://" <<<"$links" | sed "s#vmess://##" | base64 -d | jq -e ".add==\"example.com\" and .tls==\"tls\"" >/dev/null'
check "trojan allowInsecure"        'grep -q "^trojan://.*allowInsecure=1" <<<"$links"'
check "ss2022 link"                 'grep -q "^ss://2022-blake3-aes-128-gcm:" <<<"$links"'


# --- all-in-one WebSocket (443 TLS + 80 plain, four protocols via fallbacks)
echo '[]' > "$XRAY_INB"
inb_add '{"tag":"multi-ws-443","type":"multi-ws","port":443,"plain_port":80,"host":"example.com","tls":true,"insecure":false,"cert":"/c.pem","key":"/k.pem","pVless":"/abc-vless","pVmess":"/abc-vmess","pTrojan":"/abc-trojan","pSs":"/abc-ss","lVless":10801,"lVmess":10802,"lTrojan":10803,"lSs":10804}'
cfg="$(xray_build_config)"
check "multi-ws: valid JSON"            'jq -e . <<<"$cfg" >/dev/null'
check "multi-ws: api + 2 outer + 4 inner" '[ "$(jq ".inbounds|length" <<<"$cfg")" = 7 ]'
check "multi-ws: 443 is TLS, 80 is plain" '[ "$(jq -r ".inbounds[]|select(.port==443)|.streamSettings.security" <<<"$cfg")" = tls ] && [ "$(jq -r ".inbounds[]|select(.port==80)|.streamSettings.security" <<<"$cfg")" = none ]'
check "multi-ws: 4 path fallbacks"      '[ "$(jq ".inbounds[]|select(.port==443)|.settings.fallbacks|length" <<<"$cfg")" = 4 ]'
check "multi-ws: fallback dest matches inner port" '[ "$(jq -r ".inbounds[]|select(.tag==\"multi-ws-443-trojan\")|.port" <<<"$cfg")" = "$(jq -r ".inbounds[]|select(.port==443)|.settings.fallbacks[]|select(.path==\"/abc-trojan\")|.dest" <<<"$cfg")" ]'
check "multi-ws: inner inbounds are loopback WS" '[ "$(jq -r "[.inbounds[]|select(.tag|test(\"-(vless|vmess|trojan|ss)$\"))|select(.listen==\"127.0.0.1\" and .streamSettings.network==\"ws\")]|length" <<<"$cfg")" = 4 ]'
check "multi-ws: both 443 and 80 conflict-checked" '! xray_add_inbound reality 443 >/dev/null 2>&1'
links="$(xray_user_links alice)"
check "multi-ws: 8 links (4 protocols x 2 ports)" '[ "$(wc -l <<<"$links")" = 8 ]'
check "multi-ws: tls vless link"        'grep -q "^vless://.*@example.com:443?.*security=tls.*type=ws.*path=%2Fabc-vless" <<<"$links"'
check "multi-ws: plain vless on 80"     'grep -q "^vless://.*@example.com:80?.*security=none.*type=ws" <<<"$links"'
check "multi-ws: trojan ws link"        'grep -q "^trojan://.*@example.com:443?security=tls&type=ws" <<<"$links"'
check "multi-ws: ss ws link"            'grep -q "^ss://[A-Za-z0-9_-]*@example.com:80?type=ws&security=none" <<<"$links"'

check "xray log level defaults to error" '[ "$(xray_build_config | jq -r .log.loglevel)" = error ]'
setting_set xray_loglevel warning
check "xray log level overridable"       '[ "$(xray_build_config | jq -r .log.loglevel)" = warning ]'
setting_del xray_loglevel

# --- hysteria2 config
HY2_BIN=/bin/true; HY2_DIR="$TMP/hy"; HY2_CONF="$HY2_DIR/config.yaml"; mkdir -p "$HY2_DIR"
setting_set hy2_port 443; setting_set hy2_obfs secret
systemctl() { return 0; }
hy2_apply >/dev/null
check "hy2 config has users"        'grep -q "^    alice: " "$HY2_CONF" && grep -q "^    bob: " "$HY2_CONF"'
check "hy2 obfs written"            'grep -q "salamander" "$HY2_CONF"'
check "hy2 link"                    'hy2_user_link alice | grep -q "^hysteria2://alice:.*@203.0.113.7:443/?insecure=1.*obfs=salamander"'

[ $fail = 0 ] && echo "ALL TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
