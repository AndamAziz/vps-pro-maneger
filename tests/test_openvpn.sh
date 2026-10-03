#!/usr/bin/env bash
# OpenVPN UDP + TCP: both instances, shared PKI, NAT for both subnets, dual-protocol profiles, and migration
# of an existing single-protocol install. All system commands are stubbed (offline).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export VPSM_ETC="$TMP/etc" VPSM_LOG_DIR="$TMP/log" VPSM_BACKUP_DIR="$TMP/bak" VPSM_NONINTERACTIVE=1
for f in common users openvpn; do . "$ROOT/lib/$f.sh"; done
db_init; setting_set public_ip 203.0.113.9
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

OVPN_DIR="$TMP/server"; OVPN_PKI="$TMP/easy-rsa"; OVPN_CLIENTS="$TMP/clients"; SYSD="$TMP/systemd"; mkdir -p "$SYSD"
# stubs
require_root() { return 0; }
pkg_install() { return 0; }
make-cadir() { mkdir -p "$1"; }
openvpn() { echo "KEY" > "${@: -1}"; }
default_iface() { echo eth0; }
fw_allow() { echo "$1/$2" >> "$TMP/fw"; }
port_in_use() { return 1; }
sleep() { :; }
sysctl() { :; }
systemctl() { echo "$*" >> "$TMP/sysctl.log"; }
svc_active() { return 0; }
ovpn_easyrsa() {
    case "$1" in
        init-pki) mkdir -p "$OVPN_PKI/pki/issued" "$OVPN_PKI/pki/private"; : > "$OVPN_PKI/pki/index.txt" ;;
        build-ca) echo CA > "$OVPN_PKI/pki/ca.crt" ;;
        build-server-full|build-client-full)
            printf 'CERT-%s\n' "$2" > "$OVPN_PKI/pki/issued/$2.crt"; echo "PRIV-$2" > "$OVPN_PKI/pki/private/$2.key"
            echo "V	X	1	01	unknown	/CN=$2" >> "$OVPN_PKI/pki/index.txt" ;;
        gen-crl) echo CRL > "$OVPN_PKI/pki/crl.pem" ;;
        revoke) sed -i "s#^V\(.*\)/CN=$2\$#R\1/CN=$2#" "$OVPN_PKI/pki/index.txt" ;;
    esac
}
openssl() { cat "${@: -1}"; }
valid_name() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; }
OVPN_UNIT_DIR="$SYSD"
cd "$TMP" || exit 1

ovpn_install 1194 1194 >/dev/null 2>&1; rc=$?
check "install (UDP+TCP) succeeds"                    '[ $rc -eq 0 ]'
check "UDP instance: server.conf proto udp port 1194" 'grep -qx "proto udp" "$OVPN_DIR/server.conf" && grep -qx "port 1194" "$OVPN_DIR/server.conf"'
check "TCP instance: server-tcp.conf proto tcp"       'grep -qx "proto tcp" "$OVPN_DIR/server-tcp.conf" && grep -qx "port 1194" "$OVPN_DIR/server-tcp.conf"'
check "instances use different VPN subnets"           '[ "$(grep ^server "$OVPN_DIR/server.conf")" != "$(grep ^server "$OVPN_DIR/server-tcp.conf")" ]'
check "UDP has explicit-exit-notify, TCP does not"    'grep -q explicit-exit-notify "$OVPN_DIR/server.conf" && ! grep -q explicit-exit-notify "$OVPN_DIR/server-tcp.conf"'
check "settings hold both ports"                      '[ "$(setting_get ovpn_udp_port)" = 1194 ] && [ "$(setting_get ovpn_tcp_port)" = 1194 ]'
check "firewall opened for udp and tcp"               'grep -qx "1194/udp" "$TMP/fw" && grep -qx "1194/tcp" "$TMP/fw"'
nat="$SYSD/$OVPN_NAT_SVC.service"
check "NAT unit masquerades both subnets"             'grep -q "10.8.0.0/24 -o eth0" "$nat" && grep -q "10.9.0.0/24 -o eth0" "$nat"'
check "NAT unit waits for both services"              'grep "^Before=" "$nat" | grep -q "openvpn-server@server.service" && grep "^Before=" "$nat" | grep -q "openvpn-server@server-tcp.service"'
check "both services enabled and restarted"           'grep -q "openvpn-server@server-tcp" "$TMP/sysctl.log" && grep -q "restart openvpn-server@server$" "$TMP/sysctl.log"'
check "ovpn_svcs lists both units"                    '[ "$(ovpn_svcs | wc -l)" = 2 ]'

ovpn_add_client phone >/dev/null 2>&1
p="$OVPN_CLIENTS/phone.ovpn"
check "combined profile has UDP and TCP remotes"      'grep -qx "remote 203.0.113.9 1194 udp" "$p" && grep -qx "remote 203.0.113.9 1194 tcp" "$p"'
check "combined profile has no global proto line"     '! grep -q "^proto " "$p"'
check "fallback timeouts are set"                     'grep -qx "connect-timeout 10" "$p"'
check "-udp profile is UDP only"                      'grep -qx "proto udp" "$OVPN_CLIENTS/phone-udp.ovpn" && ! grep -q "remote .* tcp" "$OVPN_CLIENTS/phone-udp.ovpn"'
check "-tcp profile is TCP only"                      'grep -qx "proto tcp" "$OVPN_CLIENTS/phone-tcp.ovpn" && ! grep -q "proto udp" "$OVPN_CLIENTS/phone-tcp.ovpn"'
check "profile embeds ca/cert/key/tls-crypt"          'for t in ca cert key tls-crypt; do grep -q "^<$t>" "$p" || exit 1; done'
check "profile is private (600)"                      '[ "$(stat -c %a "$p")" = 600 ]'

ovpn_del_client phone >/dev/null 2>&1
check "revoke removes all three profiles"             '[ ! -e "$p" ] && [ ! -e "$OVPN_CLIENTS/phone-udp.ovpn" ] && [ ! -e "$OVPN_CLIENTS/phone-tcp.ovpn" ]'

# --- migration: an old UDP-only install gets TCP added, existing clients get new profiles
rm -rf "$OVPN_DIR" "$OVPN_PKI" "$OVPN_CLIENTS" "$TMP/fw"; settings_reset() { setting_del ovpn_udp_port; setting_del ovpn_tcp_port; }; settings_reset
ovpn_install 1194 1194 >/dev/null 2>&1
rm -f "$OVPN_DIR/server-tcp.conf"; settings_reset; setting_set ovpn_port 1194; setting_set ovpn_proto udp
ovpn_add_client laptop >/dev/null 2>&1
check "UDP-only profile before migration"             'grep -qx "proto udp" "$OVPN_CLIENTS/laptop.ovpn" && ! grep -q "^remote .* tcp" "$OVPN_CLIENTS/laptop.ovpn"'
ovpn_add_instance tcp 8443 >/dev/null 2>&1
check "migration adds the TCP instance on 8443"       'grep -qx "port 8443" "$OVPN_DIR/server-tcp.conf" && [ "$(ovpn_port_of tcp)" = 8443 ]'
check "migration does not touch the UDP instance"     '[ "$(ovpn_port_of udp)" = 1194 ]'
check "existing client profile now has both remotes"  'grep -qx "remote 203.0.113.9 8443 tcp" "$OVPN_CLIENTS/laptop.ovpn" && grep -qx "remote 203.0.113.9 1194 udp" "$OVPN_CLIENTS/laptop.ovpn"'

# --- legacy TCP-only install (old script allowed choosing tcp): UDP is added as the second instance
rm -rf "$OVPN_DIR" "$OVPN_PKI" "$OVPN_CLIENTS"
ovpn_install 1194 8443 >/dev/null 2>&1
sed -i 's/^proto udp$/proto tcp/;s/^port 1194$/port 443/' "$OVPN_DIR/server.conf"; rm -f "$OVPN_DIR/server-tcp.conf"
check "legacy: server.conf is the TCP instance"       '[ "$(ovpn_inst tcp)" = server ] && [ -z "$(ovpn_inst udp)" ]'
ovpn_add_instance udp 1194 >/dev/null 2>&1
check "legacy: UDP is added as server-udp"            '[ "$(ovpn_inst udp)" = server-udp ] && [ "$(ovpn_inst tcp)" = server ]'
check "legacy: subnets do not collide"                '[ "$(cat "$OVPN_DIR"/server*.conf | grep -c "^server 10.8.0.0 ")" = 1 ] && grep -q "^server 10.9.0.0 " "$OVPN_DIR/server-udp.conf"'

exit $fail
