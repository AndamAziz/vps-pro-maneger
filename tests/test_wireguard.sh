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

# --- wg_debug: the verdict follows what the kernel reports
export WG_DEBUG_CTL="$TMP/dd_control"; : > "$WG_DEBUG_CTL"
wg() { [ "${2:-}" = interfaces ] && echo wg0; }   # called as: wg show interfaces
sleep() { :; }
run_dbg() { KLOG="$1"; journalctl() { printf '%s\n' "$KLOG"; }; wg_debug 5 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }
OK_LOG=$'kernel: wireguard: wg0: Receiving handshake initiation from peer 2 (92.40.218.69:5678)\nkernel: wireguard: wg0: Sending handshake response to peer 2 (92.40.218.69:5678)'
BAD_LOG=$'kernel: wireguard: wg0: Receiving handshake initiation from peer 2 (92.40.218.69:5678)\nkernel: wireguard: wg0: Invalid handshake initiation from 92.40.218.69:5678'
out="$(run_dbg "$OK_LOG")"
check "wg_debug: request received + answered → says the answer must be lost on the way back" 'grep -q "RECEIVED" <<<"$out" && grep -q "ANSWERED" <<<"$out" && ! grep -q "REJECTED" <<<"$out"'
out="$(run_dbg "$BAD_LOG")"
check "wg_debug: invalid handshake → keys do not match, suggests a fresh config"              'grep -q "REJECTED" <<<"$out" && grep -q "wg add" <<<"$out"'
out="$(run_dbg "")"
check "wg_debug: no kernel messages → nothing reached wg"                                      'grep -q "received NO handshake request" <<<"$out"'
check "wg_debug leaves kernel debugging switched OFF afterwards" '[ "$(cat "$WG_DEBUG_CTL")" = "module wireguard -p" ]'
wg() { return 1; }
out="$(wg_debug 5 2>&1)"; rc=$?
check "wg_debug: no interface up → clear error"                                                 '[ $rc -ne 0 ] && grep -q "No WireGuard interface is up" <<<"$out"'

[ $fail = 0 ] && echo "ALL WIREGUARD TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
