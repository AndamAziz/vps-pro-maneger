#!/usr/bin/env bash
# WireGuard client generation against a PRE-EXISTING server (made by another tool, later moved to another
# port): the client config must use the live listen port and live public key, and work without our own files.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export VPSM_ETC="$TMP/etc" VPSM_LOG_DIR="$TMP/log" VPSM_BACKUP_DIR="$TMP/bak" VPSM_NONINTERACTIVE=1
for f in common users wireguard; do . "$ROOT/lib/$f.sh"; done
db_init; setting_set public_ip 203.0.113.9
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

WG_CONF="$TMP/wg0.conf"; WG_CLIENTS="$TMP/clients"      # note: clients dir and server.pub do NOT exist
cat > "$WG_CONF" <<'CONF'
[Interface]
Address = 10.66.66.1/24,fd42:42:42::1/64
ListenPort = 56590
PrivateKey = SECRET

### Client old
[Peer]
PublicKey = OLDPUB
PresharedKey = OLDPSK
AllowedIPs = 10.66.66.2/32,fd42:42:42::2/128
CONF
LIVE_PORT=443
wg() { case "$1" in
    genkey) echo "PRIVKEY-$RANDOM" ;; pubkey) read -r k; echo "PUB-of-$k" ;; genpsk) echo "PSK-$RANDOM" ;;
    show) case "$2:${3:-}" in wg0:listen-port) echo "$LIVE_PORT" ;; wg0:public-key) echo "SERVER-LIVE-PUB" ;; esac ;;
    set) return 0 ;; esac; }

wg_add_client phone >/dev/null 2>&1; rc=$?
check "works for an existing server without our own files (rc=0)"  '[ $rc -eq 0 ] && [ -f "$WG_CLIENTS/phone.conf" ]'
check "endpoint uses the LIVE listen port (443), not ListenPort 56590 / our setting" 'grep -qx "Endpoint = 203.0.113.9:443" "$WG_CLIENTS/phone.conf"'
check "client trusts the LIVE server public key"                    'grep -qx "PublicKey = SERVER-LIVE-PUB" "$WG_CLIENTS/phone.conf"'
check "next free address skips the existing peer (10.66.66.3)"      'grep -qx "Address = 10.66.66.3/32" "$WG_CLIENTS/phone.conf"'
check "peer block was appended to wg0.conf with the new address"    'grep -q "AllowedIPs = 10.66.66.3/32" "$WG_CONF"'
check "our wg_port setting is synced to the live port"              '[ "$(setting_get wg_port)" = 443 ]'
check "client config file is private (600)"                         '[ "$(stat -c %a "$WG_CLIENTS/phone.conf")" = 600 ]'

LIVE_PORT=51999; wg_add_client laptop >/dev/null 2>&1
check "a later port change is picked up by the next client"          'grep -qx "Endpoint = 203.0.113.9:51999" "$WG_CLIENTS/laptop.conf" && grep -qx "Address = 10.66.66.4/32" "$WG_CLIENTS/laptop.conf"'

LIVE_PORT=""; wg() { case "$1" in show) return 1 ;; genkey) echo K ;; pubkey) read -r k; echo P ;; genpsk) echo S ;; esac; }
out="$(wg_add_client broken 2>&1)"; rc=$?
check "interface down → clear error, no half-written client"        '[ $rc -ne 0 ] && grep -q "Cannot read the WireGuard port" <<<"$out" && [ ! -f "$WG_CLIENTS/broken.conf" ]'

# --- _fw_deltas: which rule counted the packets between two iptables-save -c snapshots
cat > "$TMP/fw_a" <<'FW'
:INPUT DROP [100:9000]
:FORWARD DROP [0:0]
[500:40000] -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[20:1600] -A ufw-before-input -m conntrack --ctstate INVALID -j DROP
[3:400] -A ufw-user-input -p udp -m udp --dport 443 -j ACCEPT
FW
cat > "$TMP/fw_b" <<'FW'
:INPUT DROP [100:9000]
:FORWARD DROP [0:0]
[900:70000] -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[31:2400] -A ufw-before-input -m conntrack --ctstate INVALID -j DROP
[3:400] -A ufw-user-input -p udp -m udp --dport 443 -j ACCEPT
FW
out="$(_fw_deltas "$TMP/fw_a" "$TMP/fw_b")"
check "_fw_deltas reports the rule whose counter grew (INVALID DROP +11)"      'grep -qP "^11\t-A ufw-before-input -m conntrack --ctstate INVALID -j DROP" <<<"$out"'
check "…and the busiest rule first, rules that did not grow are omitted"      '[ "$(head -1 <<<"$out" | cut -f1)" = 400 ] && ! grep -q "dport 443" <<<"$out"'
sed -i 's/^:INPUT DROP \[100:9000\]/:INPUT DROP [112:9500]/' "$TMP/fw_b"
check "_fw_deltas also reports growing chain policies (default DROP)"          '_fw_deltas "$TMP/fw_a" "$TMP/fw_b" | grep -qP "^12\tpolicy INPUT DROP"'

# --- wg_debug: verdict from tcpdump (arrived / size / answered) + kernel log
. "$ROOT/lib/system.sh"            # _cap_count
need_cmd() { return 0; }; get_public_ip() { echo 203.0.113.9; }; wg_live_port() { echo 443; }
export WG_DEBUG_CTL="$TMP/dd_control"; : > "$WG_DEBUG_CTL"
wg() { [ "${2:-}" = interfaces ] && echo wg0; }          # called as: wg show interfaces
sleep() { :; }; timeout() { shift; "$@"; }
IN=""; OUT=""; KLOG=""
iptables-save() { :; }; sysctl() { :; }
tcpdump() { case "$*" in *"dst port"*) printf '%b' "$IN" ;; *"src port"*) printf '%b' "$OUT" ;; esac; }
journalctl() { printf '%s\n' "$KLOG"; }
init_line() { printf '00:00:01 ens6  In  IP 92.40.218.68.5000 > 203.0.113.9.443: UDP, length 148\n'; }
dbg() { wg_debug 5 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }

IN=""; OUT=""; KLOG=""; out="$(dbg)"
check "nothing arrived → says the tunnel may not have been switched on / wrong endpoint" 'grep -q "NO packet reached UDP 443" <<<"$out"'

IN="$(for i in 1 2 3; do init_line; done)\n"; OUT=""; KLOG=""; out="$(dbg)"
check "148-byte handshakes counted and recognised"                                'grep -q "handshake initiations (148 B)   : 3" <<<"$out" && grep -q "148 bytes x3" <<<"$out"'
check "initiations arrived, nothing sent back → points at the firewall list, then keys"  'grep -q "sent NOTHING back" <<<"$out" && grep -q "firewall list above" <<<"$out" && grep -q "wg add" <<<"$out"'

KLOG=$'kernel: wireguard: wg0: Invalid handshake initiation from 92.40.218.68:5000'; out="$(dbg)"
check "kernel says Invalid → REJECTED, keys do not match"                         'grep -q "REJECTED" <<<"$out"'

KLOG=""; OUT='00:00:02 ens6  Out IP 203.0.113.9.443 > 92.40.218.68.5000: UDP, length 92\n'; out="$(dbg)"
check "server replied → says the answer must be getting lost on the way back"      'grep -q "ANSWERED" <<<"$out" && ! grep -q "REJECTED" <<<"$out"'

IN='00:00:01 ens6  In  IP 92.40.218.68.5000 > 203.0.113.9.443: UDP, length 1200\n'; OUT=""; KLOG=""; out="$(dbg)"
check "non-148-byte packets (QUIC from a browser) are not mistaken for WireGuard"  'grep -q "none is a WireGuard handshake" <<<"$out"'

wg() { return 1; }
out="$(wg_debug 5 2>&1)"; rc=$?
check "no interface up → clear error"                                               '[ $rc -ne 0 ] && grep -q "No WireGuard interface is up" <<<"$out"'
check "wg_debug leaves kernel debugging switched OFF afterwards"                   '[ "$(cat "$WG_DEBUG_CTL")" = "module wireguard -p" ]'

[ $fail = 0 ] && echo "ALL WIREGUARD TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
