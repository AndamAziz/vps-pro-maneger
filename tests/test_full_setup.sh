#!/usr/bin/env bash
# Offline tests for the unattended full setup: step order, continue-after-failure, domain fallback,
# SSH-port detection and the firewall lock-out guard. Every installer/system call is stubbed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export VPSM_ETC="$TMP/etc" VPSM_LOG_DIR="$TMP/log" VPSM_BACKUP_DIR="$TMP/bak" VPSM_NONINTERACTIVE=1
for f in common users ssl xray hysteria wireguard openvpn squid ssh system bot; do . "$ROOT/lib/$f.sh"; done
db_init
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

CALLS=()
rec() { CALLS+=("$1"); }
require_root() { :; }
# --- stubs
sys_enable_bbr() { rec bbr; }; sys_tune() { rec tune; }; sys_swap() { rec swap; }
sys_fail2ban() { rec fail2ban; }; xray_installed() { return 1; }; xray_install() { rec xray_install; }
xray_inbound_exists() { return 1; }
xray_add_inbound() { rec "xray_add:$1:$2:${3:-}:${4:-}"; }
hy2_installed() { return 1; }; hy2_install() { rec "hy2:$*"; }
wg_installed() { return 1; }; wg_install() { rec wg; [ -z "${FAIL_WG:-}" ]; }
ovpn_installed() { return 1; }; ovpn_install() { rec ovpn; }
squid_installed() { return 1; }; squid_install() { rec "squid:$1"; }
udpgw_install() { rec "udpgw:$1"; }; sshws_installed() { return 1; }; sshws_install() { rec sshws; }; apply_all() { rec apply; }; fw_enable() { rec ufw; }
ssl_issue() { rec "ssl:$1"; return 1; }
user_show() { rec "show:$1"; }; sys_ports() { :; }
svc_active() { return 1; }; free() { echo "Mem: 838 0 0 0 0 0"; }; swapon() { :; }

# 1) happy path
CALLS=(); full_setup alice >/dev/null 2>&1; rc=$?
check "full setup returns 0 when every step works" '[ $rc -eq 0 ]'
check "step order: tune → fail2ban → xray → WS → reality → hy2 → wg → ovpn → squid → udpgw → sshws → firewall" \
  '[ "$(printf "%s " "${CALLS[@]}" | grep -oE "tune|fail2ban|xray_install|xray_add:multi-ws|xray_add:reality|hy2|wg|ovpn|squid|udpgw|sshws|ufw" | tr "\n" " ")" = "tune fail2ban xray_install xray_add:multi-ws xray_add:reality hy2 wg ovpn squid udpgw sshws ufw " ]'
check "WS on 443 + plain 80"         'printf "%s\n" "${CALLS[@]}" | grep -qx "xray_add:multi-ws:443::80"'
check "Reality on 8443"              'printf "%s\n" "${CALLS[@]}" | grep -qx "xray_add:reality:8443::www.microsoft.com"'
check "Hysteria2 self-signed on 443" 'printf "%s\n" "${CALLS[@]}" | grep -qx "hy2:443 -"'
check "Squid on 8080"                'printf "%s\n" "${CALLS[@]}" | grep -qx "squid:8080"'
check "user 'alice' created"         '[ "$(jq -r ".[0].name" "$USERS_DB")" = alice ]'
check "swap created on 838 MB RAM"   'printf "%s\n" "${CALLS[@]}" | grep -qx swap'
check "links shown for the user"     'printf "%s\n" "${CALLS[@]}" | grep -qx "show:alice"'

# 2) a failing step does not stop the rest
CALLS=(); FAIL_WG=1; out="$(full_setup bob 2>&1)"; rc=$?
CALLS=(); full_setup bob >/dev/null 2>&1
unset FAIL_WG
check "failing WireGuard → non-zero exit"         '[ $rc -ne 0 ]'
check "…but OpenVPN/Squid/UDPGW/firewall still ran" 'printf "%s\n" "${CALLS[@]}" | grep -qx ovpn && printf "%s\n" "${CALLS[@]}" | grep -qx "squid:8080" && printf "%s\n" "${CALLS[@]}" | grep -qx "udpgw:7300" && printf "%s\n" "${CALLS[@]}" | grep -qx ufw'
check "summary lists the failed step"             'grep -q "✖.*WireGuard" <<<"$out"'

# 3) domain given but certificate cannot be issued → falls back to self-signed/IP, setup continues
CALLS=(); full_setup carol example.test >/dev/null 2>&1
check "tries to issue the certificate"            'printf "%s\n" "${CALLS[@]}" | grep -qx "ssl:example.test"'
check "falls back to empty domain for WS"         'printf "%s\n" "${CALLS[@]}" | grep -qx "xray_add:multi-ws:443::80"'

# 4) SSH port detection: default 22 even when sshd_config has only "#Port 22"
SSHD_CONF="$TMP/sshd_config"; printf '#Port 22\nPermitRootLogin yes\n' > "$SSHD_CONF"
sshd() { return 1; }; ss() { return 0; }
check "ssh_current_ports → 22 when Port is commented out" '[ "$(ssh_current_ports | xargs)" = 22 ]'
printf 'Port 2222\n' > "$SSHD_CONF"
check "ssh_current_ports reads an explicit Port"          '[ "$(ssh_current_ports | xargs)" = 2222 ]'
sshd() { [ "$1" = -T ] && printf 'port 2200\nport 22\n'; }
check "ssh_current_ports prefers sshd -T (effective)"     '[ "$(ssh_current_ports | xargs)" = "22 2200" ]'

# 5) firewall lock-out guard
unset -f fw_enable; . "$ROOT/lib/system.sh"
require_root() { :; }; pkg_install() { return 0; }
UFW=(); ADDED=""
ufw() { case "$1" in show) printf '%s' "$ADDED" ;; *) UFW+=("$*") ;; esac; }
sshd() { [ "$1" = -T ] && printf 'port 22\n'; }
ADDED=""; UFW=(); fw_enable >/dev/null 2>&1; rc=$?
check "ufw NOT enabled when SSH is not in the allowed set" '[ $rc -ne 0 ] && ! printf "%s\n" "${UFW[@]}" | grep -q -- "--force enable"'
ADDED=$'ufw allow 22/tcp\n'; UFW=(); fw_enable >/dev/null 2>&1; rc=$?
check "ufw enabled once SSH is allowed"                   '[ $rc -eq 0 ] && printf "%s\n" "${UFW[@]}" | grep -q -- "--force enable"'
check "SSH rule is added before enabling"                 'printf "%s\n" "${UFW[@]}" | grep -qx "allow 22/tcp"'

# 6) ports of services that are really running are opened (WireGuard on UDP 443, hysteria on 666 ...)
wg() { case "$1" in interfaces) echo wg0 ;; show) echo 443 ;; esac; }
ss() { cat <<'SS'
udp   UNCONN 0 0 0.0.0.0:443     0.0.0.0:*
udp   UNCONN 0 0 *:666           *:*  users:(("hysteria",pid=1,fd=3))
tcp   LISTEN 0 4 0.0.0.0:8443    0.0.0.0:*  users:(("xray",pid=2,fd=4))
tcp   LISTEN 0 4 127.0.0.1:10801 0.0.0.0:*  users:(("xray",pid=2,fd=5))
tcp   LISTEN 0 4 *:8080          *:*  users:(("squid",pid=3,fd=6))
udp   UNCONN 0 0 *:19809         *:*  users:(("squid",pid=3,fd=7))
tcp   LISTEN 0 4 127.0.0.1:44870 0.0.0.0:*  users:(("httpd",pid=9,fd=3))
SS
}
ADDED=$'ufw allow 22/tcp\n'; UFW=(); fw_enable >/dev/null 2>&1
check "WireGuard's real UDP port (443) is allowed"      'printf "%s\n" "${UFW[@]}" | grep -qx "allow 443/udp"'
check "hysteria's real UDP port (666) is allowed"       'printf "%s\n" "${UFW[@]}" | grep -qx "allow 666/udp"'
check "xray public TCP port (8443) is allowed"          'printf "%s\n" "${UFW[@]}" | grep -qx "allow 8443/tcp"'
check "squid TCP port is allowed, its random UDP not"   'printf "%s\n" "${UFW[@]}" | grep -qx "allow 8080/tcp" && ! printf "%s\n" "${UFW[@]}" | grep -q "19809"'
check "loopback-only listeners are NOT opened"          '! printf "%s\n" "${UFW[@]}" | grep -qE "10801|44870"'

# 7) sys_ports labels WireGuard's process-less UDP socket and keeps ufw tcp/udp rules apart
out="$(sys_ports 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
check "ports table names the WireGuard socket (udp 443)"  'grep -Eq "^udp +443 +wireguard" <<<"$out"'
check "other sockets keep their process names"            'grep -Eq "^udp +666 +hysteria" <<<"$out"'
fw_active() { return 0; }
ufw() { case "$1" in status) printf 'Status: active\n443/tcp ALLOW Anywhere\n443/udp ALLOW Anywhere\n22/tcp ALLOW Anywhere\n443/tcp (v6) ALLOW Anywhere (v6)\n' ;; esac; }
out="$(sys_ports 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
check "ufw summary lists 443/tcp AND 443/udp"             'grep -q "443/tcp" <<<"$out" && grep -q "443/udp" <<<"$out"'

# 8) xray/squid ephemeral UDP sockets: hidden in `ports`, never opened by the firewall
ss() { cat <<'SS'
tcp   LISTEN 0 4 0.0.0.0:443     0.0.0.0:*  users:(("xray",pid=2,fd=4))
udp   UNCONN 0 0 0.0.0.0:666     0.0.0.0:*  users:(("hysteria",pid=1,fd=3))
udp   UNCONN 0 0 0.0.0.0:8388    0.0.0.0:*  users:(("xray",pid=2,fd=9))
udp   UNCONN 0 0 *:10299         *:*  users:(("xray",pid=2,fd=11))
udp   UNCONN 0 0 *:10923         *:*  users:(("xray",pid=2,fd=12))
udp   UNCONN 0 0 *:19809         *:*  users:(("squid",pid=3,fd=7))
udp   UNCONN 0 0 127.0.0.1:10804 0.0.0.0:*  users:(("xray",pid=2,fd=13))
SS
}
mkdir -p "$TMP/etc"; echo '[{"tag":"ss2022-8388","type":"ss2022","port":8388,"serverKey":"k"}]' > "$XRAY_INB"
wg() { :; }; fw_active() { return 1; }
out="$(sys_ports 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
check "random xray UDP sockets are hidden"                '! grep -Eq "10299|10923|19809" <<<"$out"'
check "…and the hidden ones are counted for the user"     'grep -q "3 temporary UDP sockets" <<<"$out"'
check "a real Shadowsocks-2022 UDP inbound stays visible" 'grep -Eq "^udp +8388 +xray" <<<"$out"'
check "hysteria and xray TCP stay visible"                'grep -Eq "^udp +666 +hysteria" <<<"$out" && grep -Eq "^tcp +443 +xray" <<<"$out"'
check "ephemeral sockets are not counted as open ports"   'grep -q "Open to the internet: 1 TCP + 2 UDP" <<<"$out"'
# (section 7 replaced the ufw stub; restore the recording one, otherwise nothing is captured)
UFW=(); ADDED=$'ufw allow 22/tcp\n'
ufw() { case "$1" in show) printf '%s' "$ADDED" ;; *) UFW+=("$*") ;; esac; }
fw_enable >/dev/null 2>&1
check "the recorder captured the firewall rules"          '[ "${#UFW[@]}" -gt 3 ]'
check "firewall does NOT open xray's random UDP ports"    '! printf "%s\n" "${UFW[@]}" | grep -qE "10299|10923|19809"'
check "firewall still opens hysteria 666/udp + xray 443"  'printf "%s\n" "${UFW[@]}" | grep -qx "allow 666/udp" && printf "%s\n" "${UFW[@]}" | grep -qx "allow 443/tcp"'

# 9) `watch` rows: real packets only, and "arrived" is told apart from "answered"
printf '\n' > "$TMP/empty.cap"
printf '01:11:50.655638 ens6  In  IP 92.40.219.136.1869 > 213.171.212.110.80: Flags [S], length 0\n01:11:50.656001 ens6  In  IP 92.40.219.136.1871 > 213.171.212.110.80: Flags [S], length 0\n01:11:51.100000 ens6  In  IP 198.51.100.7.5555 > 213.171.212.110.80: Flags [S], length 0\n\n' > "$TMP/in.cap"
printf '01:11:50.656100 ens6  Out IP 213.171.212.110.80 > 92.40.219.136.1869: Flags [S.], length 0\n\n' > "$TMP/out.cap"
row() { _watch_row "$@" | sed 's/\x1b\[[0-9;]*m//g'; }
check "an empty capture shows 0 arrived, 0 answered"          'grep -Eq "TCP 8443 +arrived +0 +answered +0" <<<"$(row "TCP 8443" "$TMP/empty.cap" "$TMP/empty.cap")"'
out="$(row "TCP 80" "$TMP/in.cap" "$TMP/out.cap")"
check "3 SYNs arrived, 1 SYN-ACK answered"                    'grep -Eq "arrived +3 +answered +1" <<<"$out"'
check "top sources are listed with their counts"              'grep -q "92.40.219.136 (2)" <<<"$out" && grep -q "198.51.100.7 (1)" <<<"$out"'
out="$(row "TCP 8080" "$TMP/in.cap" "$TMP/empty.cap")"
check "arrived but answered 0 (firewall drop) is visible"     'grep -Eq "arrived +3 +answered +0" <<<"$out"'

# a SYN scanner that never completes the handshake makes the server retransmit its SYN-ACK: still ONE connection
printf '00:00:01 ens6  In  IP 185.224.128.16.40000 > 213.171.212.110.443: Flags [S], length 0\n\n' > "$TMP/scan_in.cap"
for i in 1 2 3 4 5 6; do printf '00:00:0%d ens6  Out IP 213.171.212.110.443 > 185.224.128.16.40000: Flags [S.], length 0\n' "$i"; done > "$TMP/scan_out.cap"
out="$(row "TCP 443" "$TMP/scan_in.cap" "$TMP/scan_out.cap")"
check "SYN-ACK retransmissions count as ONE answered connection" 'grep -Eq "arrived +1 +answered +1" <<<"$out"'
out="$(_watch_row "UDP 443" "$TMP/in.cap" "$TMP/empty.cap" packets | sed 's/\x1b\[[0-9;]*m//g')"
check "UDP rows still count packets (WireGuard retries are informative)" 'grep -Eq "arrived +3 +answered +0" <<<"$out"'

[ $fail = 0 ] && echo "ALL FULL-SETUP TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
