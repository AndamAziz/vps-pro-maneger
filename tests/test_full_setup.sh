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
udpgw_install() { rec "udpgw:$1"; }; apply_all() { rec apply; }; fw_enable() { rec ufw; }
ssl_issue() { rec "ssl:$1"; return 1; }
user_show() { rec "show:$1"; }; sys_ports() { :; }
svc_active() { return 1; }; free() { echo "Mem: 838 0 0 0 0 0"; }; swapon() { :; }

# 1) happy path
CALLS=(); full_setup alice >/dev/null 2>&1; rc=$?
check "full setup returns 0 when every step works" '[ $rc -eq 0 ]'
check "step order: tune → fail2ban → xray → WS → reality → hy2 → wg → ovpn → squid → udpgw → firewall" \
  '[ "$(printf "%s " "${CALLS[@]}" | grep -oE "tune|fail2ban|xray_install|xray_add:multi-ws|xray_add:reality|hy2|wg|ovpn|squid|udpgw|ufw" | tr "\n" " ")" = "tune fail2ban xray_install xray_add:multi-ws xray_add:reality hy2 wg ovpn squid udpgw ufw " ]'
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

[ $fail = 0 ] && echo "ALL FULL-SETUP TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
