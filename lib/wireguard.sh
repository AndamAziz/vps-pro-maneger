#!/usr/bin/env bash
#==============================================================================
# WireGuard
#==============================================================================

WG_IF="wg0"
WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/$WG_IF.conf"
WG_CLIENTS="$VPSM_ETC/wireguard"
WG_NET="10.66.66"

wg_installed() { [ -f "$WG_CONF" ]; }

# An existing WireGuard (made by another tool, or moved to another port later) may differ from our own
# settings, so always ask the running interface first.
wg_live_port() {
    local p; p="$(wg show "$WG_IF" listen-port 2>/dev/null)"
    if [ -n "$p" ] && [ "$p" != 0 ]; then echo "$p"; else setting_get wg_port; fi
}
wg_server_pub() { wg show "$WG_IF" public-key 2>/dev/null || cat "$WG_CLIENTS/server.pub" 2>/dev/null; }

wg_install() {
    require_root
    wg_installed && { warn "WireGuard is already configured."; return 0; }
    local port iface
    port="$(ask_port "WireGuard (UDP)" 51820 udp)" || return 1
    iface="$(default_iface)"
    [ -n "$iface" ] || { err "Cannot detect the default network interface."; return 1; }

    info "Installing WireGuard..."
    pkg_install wireguard wireguard-tools iptables qrencode || return 1
    mkdir -p "$WG_DIR" "$WG_CLIENTS"; chmod 700 "$WG_DIR" "$WG_CLIENTS"

    local priv pub
    priv="$(wg genkey)"; pub="$(echo "$priv" | wg pubkey)"
    cat > "$WG_CONF" <<EOF
[Interface]
Address = ${WG_NET}.1/24
ListenPort = $port
PrivateKey = $priv
PostUp = iptables -I FORWARD -i %i -j ACCEPT; iptables -I FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -s ${WG_NET}.0/24 -o $iface -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -s ${WG_NET}.0/24 -o $iface -j MASQUERADE
EOF
    chmod 600 "$WG_CONF"
    echo "$pub" > "$WG_CLIENTS/server.pub"
    setting_set wg_port "$port"

    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-vpsm-forward.conf
    sysctl -p /etc/sysctl.d/99-vpsm-forward.conf >/dev/null 2>&1
    fw_allow "$port" udp
    systemctl enable --now "wg-quick@$WG_IF" >/dev/null 2>&1 \
        && ok "WireGuard installed on UDP/$port" || { err "WireGuard failed to start (journalctl -u wg-quick@$WG_IF)"; return 1; }
    log_action "wireguard installed"
}

wg_next_ip() {
    local i
    for i in $(seq 2 254); do
        grep -qs "AllowedIPs = ${WG_NET}.$i/32" "$WG_CONF" || { echo "${WG_NET}.$i"; return; }
    done
    return 1
}

wg_add_client() { # wg_add_client NAME
    local name="$1" ip priv pub psk port server_pub endpoint
    wg_installed || { err "WireGuard is not installed."; return 1; }
    valid_name "$name" || { err "Invalid name."; return 1; }
    mkdir -p "$WG_CLIENTS"; chmod 700 "$WG_CLIENTS"
    [ -f "$WG_CLIENTS/$name.conf" ] && { err "Client '$name' already exists."; return 1; }
    ip="$(wg_next_ip)" || { err "Address pool exhausted."; return 1; }
    priv="$(wg genkey)"; pub="$(echo "$priv" | wg pubkey)"; psk="$(wg genpsk)"
    port="$(wg_live_port)"; server_pub="$(wg_server_pub)"
    [ -n "$port" ] && [ -n "$server_pub" ] || { err "Cannot read the WireGuard port / public key (is $WG_IF up?)."; return 1; }
    setting_set wg_port "$port"
    endpoint="$(get_public_ip):$port"

    cat >> "$WG_CONF" <<EOF

# BEGIN peer $name
[Peer]
PublicKey = $pub
PresharedKey = $psk
AllowedIPs = $ip/32
# END peer $name
EOF
    # apply live without disturbing other clients
    wg set "$WG_IF" peer "$pub" preshared-key <(echo "$psk") allowed-ips "$ip/32" 2>/dev/null

    cat > "$WG_CLIENTS/$name.conf" <<EOF
[Interface]
PrivateKey = $priv
Address = $ip/32
DNS = 1.1.1.1, 8.8.8.8
MTU = 1380

[Peer]
PublicKey = $server_pub
PresharedKey = $psk
Endpoint = $endpoint
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    chmod 600 "$WG_CLIENTS/$name.conf"
    log_action "wireguard client added: $name"
    ok "Client '$name' created → $WG_CLIENTS/$name.conf"
}

wg_del_client() {
    local name="$1" pub
    [ -f "$WG_CLIENTS/$name.conf" ] || { err "Client '$name' not found."; return 1; }
    pub="$(awk -v n="$name" '$0=="# BEGIN peer "n {f=1} f && /^PublicKey/ {print $3; exit}' "$WG_CONF")"
    [ -n "$pub" ] && wg set "$WG_IF" peer "$pub" remove 2>/dev/null
    sed -i "/^# BEGIN peer $name\$/,/^# END peer $name\$/d" "$WG_CONF"
    rm -f "$WG_CLIENTS/$name.conf"
    log_action "wireguard client removed: $name"
    ok "Client '$name' removed"
}

wg_list_clients() {
    ls "$WG_CLIENTS"/*.conf >/dev/null 2>&1 || { echo "No clients."; return; }
    for f in "$WG_CLIENTS"/*.conf; do
        basename "$f" .conf | while read -r n; do
            echo "  • $n  ($(awk '/^Address/{print $3}' "$f"))"
        done
    done
    echo ""; wg show "$WG_IF" 2>/dev/null | grep -E "peer|latest handshake|transfer" || true
}

wg_show_client() {
    local f="$WG_CLIENTS/$1.conf"
    [ -f "$f" ] || { err "Client '$1' not found."; return 1; }
    cat "$f"; echo ""; show_qr "$(cat "$f")"
}

# wg_debug [seconds] - find out why a WireGuard handshake does (not) complete. Connect the tunnel on your
# phone while it runs. It combines three independent sources, because any single one can be misleading:
#   1. tcpdump: did UDP packets reach the server, how big are they (a handshake initiation is exactly 148 bytes),
#      and did the server send anything back
#   2. the kernel's wireguard debug messages (received / invalid / answered)
#   3. the peers' handshake times
wg_debug() {
    local secs="${1:-40}" ctl="${WG_DEBUG_CTL:-/sys/kernel/debug/dynamic_debug/control}" mark log
    local port ip tmp arrived answered inits sizes left kdbg=1 now ifc pk ts hs
    [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -ge 5 ] && [ "$secs" -le 300 ] || { err "Seconds must be 5-300."; return 1; }
    [ -n "$(wg show interfaces 2>/dev/null)" ] || { err "No WireGuard interface is up."; return 1; }
    need_cmd tcpdump || return 1
    port="$(wg_live_port)"; ip="$(get_public_ip)"; tmp="$(mktemp -d)"

    [ -w "$ctl" ] || mount -t debugfs none /sys/kernel/debug 2>/dev/null
    if [ -w "$ctl" ] && echo 'module wireguard +p' > "$ctl" 2>/dev/null; then :; else kdbg=0; fi
    mark="$(date '+%Y-%m-%d %H:%M:%S')"
    timeout "$secs" tcpdump -nn -l -i any "udp dst port $port and dst host $ip" > "$tmp/in" 2>/dev/null &
    timeout "$secs" tcpdump -nn -l -i any "udp src port $port and src host $ip" > "$tmp/out" 2>/dev/null &

    echo -e "${BOLD}${YELLOW}▶ Switch the WireGuard tunnel ON now, on your phone/PC (watching UDP $port for ${secs}s).${NC}"
    left="$secs"
    while [ "$left" -gt 0 ]; do
        sleep $(( left > 15 ? 15 : left )); left=$(( left > 15 ? left - 15 : 0 ))
        [ "$left" -gt 0 ] && echo "  ... ${left}s left"
    done
    wait
    [ "$kdbg" = 1 ] && echo 'module wireguard -p' > "$ctl" 2>/dev/null

    arrived="$(_cap_count "$tmp/in")"; answered="$(_cap_count "$tmp/out")"; arrived="${arrived:-0}"; answered="${answered:-0}"
    inits="$(grep -cE 'length 148$' "$tmp/in" 2>/dev/null || true)"; inits="${inits:-0}"
    sizes="$(grep -oE 'length [0-9]+' "$tmp/in" 2>/dev/null | sort | uniq -c | sort -rn | head -3 | awk '{printf "%s bytes x%s   ", $3, $1}')"
    log="$(journalctl -k --since "$mark" --no-pager 2>/dev/null | grep -i 'wireguard:' | sed 's/^.*wireguard: //' | tail -30)"

    echo -e "\n${BOLD}Network (UDP $port)${NC}"
    echo "  packets that reached the server : $arrived   ${sizes:+(sizes: $sizes)}"
    echo "  packets the server sent back    : $answered"
    echo "  handshake initiations (148 B)   : $inits"
    echo -e "\n${BOLD}Kernel messages${NC}"
    if [ -n "$log" ]; then echo "$log" | sed 's/^/  /'
    elif [ "$kdbg" = 0 ]; then echo "  (kernel debugging is not available on this server - rely on the network numbers above)"
    else echo "  (none)"; fi
    echo -e "\n${BOLD}Peers${NC}"
    now="$(date +%s)"
    for ifc in $(wg show interfaces); do
        while read -r pk ts; do
            if [ "${ts:-0}" = 0 ]; then hs="${RED}NEVER${NC}"; else hs="${GREEN}$((now - ts))s ago${NC}"; fi
            echo -e "  peer ${pk:0:10}…  handshake: $hs"
        done < <(wg show "$ifc" latest-handshakes 2>/dev/null)
    done

    echo -e "\n${BOLD}Verdict${NC}"
    if [ "$arrived" -eq 0 ]; then
        err "NO packet reached UDP $port during the window. Either the tunnel was not switched on while this ran, or the phone sends to another port/address (check the Endpoint in its config: it must be $ip:$port), or the network blocks it before the server."
    elif [ "$inits" -eq 0 ]; then
        warn "$arrived packet(s) arrived, but none is a WireGuard handshake (those are 148 bytes). They are probably something else, e.g. a browser trying QUIC / HTTP3 on UDP 443."
    else
        ok "$inits WireGuard handshake request(s) reached the server - the network path to it works."
        if grep -qiE "Invalid (MAC|handshake)" <<<"$log"; then
            err "...and the server REJECTED them: the keys do not match (wrong server public key, or this client's key / PresharedKey is not the registered one). Delete the tunnel in the app and import a FRESH config: vpsmanager wg add <new-name>"
        elif [ "$answered" -gt 0 ] || grep -q "Sending handshake response" <<<"$log"; then
            ok "...and the server ANSWERED ($answered packet(s)). If the app still shows no handshake, the answer does not get back to the phone (this network drops UDP replies from that port - try another port)."
        else
            err "...but the server sent NOTHING back. WireGuard silently drops handshakes it cannot verify, so this is almost certainly a KEY mismatch. Delete the tunnel in the app and import a FRESH config: vpsmanager wg add <new-name>"
        fi
    fi
    rm -rf "$tmp"
}

wg_menu() {
    while true; do
        menu_header "🛡️  WireGuard   [$(svc_state "wg-quick@$WG_IF")]"
        echo "  1) Install WireGuard"
        echo "  2) Add client (config + QR)"
        echo "  3) Show client config / QR"
        echo "  4) Delete client"
        echo "  5) List clients / status"
        echo "  6) Restart"
        echo "  7) Uninstall"
        echo "  0) Back"
        echo -e "$LINE"
        case "$(ask "Choose" "")" in
            1) wg_install; pause ;;
            2) local cn; cn="$(ask "Client name" "")"
               wg_add_client "$cn" && wg_show_client "$cn"; pause ;;
            3) wg_list_clients; wg_show_client "$(ask "Client name" "")"; pause ;;
            4) wg_list_clients; wg_del_client "$(ask "Client name" "")"; pause ;;
            5) wg_list_clients; pause ;;
            6) svc_restart "wg-quick@$WG_IF"; pause ;;
            7) if confirm "Remove WireGuard and all clients?" n; then
                   systemctl disable --now "wg-quick@$WG_IF" >/dev/null 2>&1
                   rm -rf "$WG_CONF" "$WG_CLIENTS"; ok "WireGuard removed"
               fi; pause ;;
            0|"") return ;;
        esac
    done
}
