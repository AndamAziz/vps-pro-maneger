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
    [ -f "$WG_CLIENTS/$name.conf" ] && { err "Client '$name' already exists."; return 1; }
    ip="$(wg_next_ip)" || { err "Address pool exhausted."; return 1; }
    priv="$(wg genkey)"; pub="$(echo "$priv" | wg pubkey)"; psk="$(wg genpsk)"
    port="$(setting_get wg_port)"; server_pub="$(cat "$WG_CLIENTS/server.pub")"
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
