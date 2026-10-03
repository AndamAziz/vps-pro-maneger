#!/usr/bin/env bash
#==============================================================================
# OpenVPN (easy-rsa 3, ECDSA, tls-crypt, AES-256-GCM)
#==============================================================================

OVPN_DIR="/etc/openvpn/server"
OVPN_PKI="/etc/openvpn/easy-rsa"
OVPN_CLIENTS="$VPSM_ETC/openvpn"
OVPN_NAT_SVC="vpsm-openvpn-nat"
OVPN_UNIT_DIR="/etc/systemd/system"

ovpn_installed() { compgen -G "$OVPN_DIR/server*.conf" >/dev/null 2>&1; }

ovpn_easyrsa() { (cd "$OVPN_PKI" && EASYRSA_BATCH=1 EASYRSA_ALGO=ec EASYRSA_CURVE=prime256v1 ./easyrsa "$@" >/dev/null 2>&1); }

# Instance name (server / server-tcp ...) whose config uses PROTO ('' if none)
ovpn_inst() { # ovpn_inst udp|tcp
    local f
    for f in "$OVPN_DIR"/server*.conf; do
        [ -f "$f" ] || continue
        grep -q "^proto $1\$" "$f" && { basename "$f" .conf; return 0; }
    done
    return 1
}

ovpn_port_of() { # ovpn_port_of udp|tcp
    local i; i="$(ovpn_inst "$1")" || return 1
    awk '$1=="port"{print $2; exit}' "$OVPN_DIR/$i.conf"
}

# systemd units of all installed instances
ovpn_svcs() {
    local f
    for f in "$OVPN_DIR"/server*.conf; do
        [ -f "$f" ] && echo "openvpn-server@$(basename "$f" .conf)"
    done
}

ovpn_state_line() { # udp|tcp
    local i; i="$(ovpn_inst "$1")" || { echo -e "${DIM}not installed${NC}"; return; }
    echo "$(svc_state "openvpn-server@$i") (port $(ovpn_port_of "$1"))"
}

ovpn_restart_all() { local s; for s in $(ovpn_svcs); do svc_restart "$s"; done; }

ovpn_write_server_conf() { # NAME PROTO PORT SUBNET
    local name="$1" proto="$2" port="$3" net="$4"
    mkdir -p /var/lib/openvpn
    cat > "$OVPN_DIR/$name.conf" <<EOF
port $port
proto $proto
dev tun
ca ca.crt
cert server.crt
key server.key
dh none
ecdh-curve prime256v1
tls-crypt tls-crypt.key
crl-verify crl.pem
topology subnet
server $net 255.255.255.0
ifconfig-pool-persist /var/lib/openvpn/ipp-$name.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-GCM
auth SHA256
tls-version-min 1.2
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn-status-$name.log 10
verb 3
$([ "$proto" = udp ] && echo "explicit-exit-notify 1")
$([ "$proto" = tcp ] && echo "tcp-nodelay")
EOF
}

# NAT/forward rules for every instance subnet
ovpn_write_nat() {
    local iface f net up="" down="" units=""
    iface="$(default_iface)"; [ -n "$iface" ] || { err "Cannot detect the default network interface."; return 1; }
    for f in "$OVPN_DIR"/server*.conf; do
        [ -f "$f" ] || continue
        net="$(awk '$1=="server"{print $2; exit}' "$f")"
        units="$units openvpn-server@$(basename "$f" .conf).service"
        up="$up
ExecStart=/sbin/iptables -t nat -A POSTROUTING -s $net/24 -o $iface -j MASQUERADE
ExecStart=/sbin/iptables -I FORWARD -s $net/24 -j ACCEPT"
        down="$down
ExecStop=-/sbin/iptables -t nat -D POSTROUTING -s $net/24 -o $iface -j MASQUERADE
ExecStop=-/sbin/iptables -D FORWARD -s $net/24 -j ACCEPT"
    done
    cat > "$OVPN_UNIT_DIR/$OVPN_NAT_SVC.service" <<EOF
[Unit]
Description=NAT rules for OpenVPN (UDP + TCP)
After=network-online.target
Before=${units# }

[Service]
Type=oneshot
RemainAfterExit=yes$up
ExecStart=/sbin/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT$down
ExecStop=-/sbin/iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

# Create the PKI + shared keys once
ovpn_init_pki() {
    [ -f "$OVPN_DIR/server.crt" ] && return 0
    pkg_install openvpn easy-rsa iptables openssl || return 1
    rm -rf "$OVPN_PKI"; make-cadir "$OVPN_PKI" || { err "make-cadir failed"; return 1; }
    info "Building PKI (ECDSA)..."
    ovpn_easyrsa init-pki || return 1
    ovpn_easyrsa build-ca nopass || return 1
    ovpn_easyrsa build-server-full server nopass || return 1
    ovpn_easyrsa gen-crl || return 1
    mkdir -p "$OVPN_DIR" "$OVPN_CLIENTS"
    cp "$OVPN_PKI/pki/ca.crt" "$OVPN_PKI/pki/issued/server.crt" "$OVPN_PKI/pki/private/server.key" "$OVPN_DIR/"
    cp "$OVPN_PKI/pki/crl.pem" "$OVPN_DIR/crl.pem"; chmod 644 "$OVPN_DIR/crl.pem"
    openvpn --genkey secret "$OVPN_DIR/tls-crypt.key" 2>/dev/null || openvpn --genkey --secret "$OVPN_DIR/tls-crypt.key"
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-vpsm-forward.conf
    sysctl -p /etc/sysctl.d/99-vpsm-forward.conf >/dev/null 2>&1
}

# ovpn_add_instance udp|tcp [PORT]  - add one protocol instance (no-op if present)
ovpn_add_instance() {
    local proto="$1" port="${2:-}" name net def
    ovpn_inst "$proto" >/dev/null && { ok "OpenVPN ${proto^^} already installed (port $(ovpn_port_of "$proto"))"; return 0; }
    ovpn_init_pki || return 1
    mkdir -p "$OVPN_DIR" "$OVPN_CLIENTS"
    # TCP 443/80 belong to Xray by default, so TCP uses 1194 as well
    def=1194
    if [ -z "$port" ]; then port="$(ask_port "OpenVPN ${proto^^}" "$def" "$proto")" || return 1; fi
    valid_port "$port" || { err "Invalid port."; return 1; }
    port_in_use "$port" "$proto" && { err "Port $port/$proto is already in use."; return 1; }
    name=server; [ -f "$OVPN_DIR/server.conf" ] && name="server-$proto"
    net=10.8.0.0; grep -qs "^server 10.8.0.0 " "$OVPN_DIR"/server*.conf && net=10.9.0.0
    ovpn_write_server_conf "$name" "$proto" "$port" "$net"
    setting_set "ovpn_${proto}_port" "$port"
    ovpn_write_nat || return 1
    fw_allow "$port" "$proto"
    systemctl enable "$OVPN_NAT_SVC" "openvpn-server@$name" >/dev/null 2>&1
    systemctl restart "$OVPN_NAT_SVC" >/dev/null 2>&1
    systemctl restart "openvpn-server@$name" >/dev/null 2>&1
    sleep 1
    if svc_active "openvpn-server@$name"; then
        ok "OpenVPN ${proto^^} running on port $port"
    else
        err "OpenVPN ${proto^^} failed to start (journalctl -u openvpn-server@$name -n 30)"; return 1
    fi
    ovpn_regen_profiles
    log_action "openvpn $proto instance on $port"
}

# Install: UDP and TCP together (ports can be given: ovpn_install [UDP_PORT] [TCP_PORT])
ovpn_install() {
    require_root
    local up="${1:-}" tp="${2:-}" rc=0
    info "Installing OpenVPN (UDP + TCP)..."
    ovpn_add_instance udp "$up" || rc=1
    ovpn_add_instance tcp "$tp" || rc=1
    return $rc
}

# Write the .ovpn for NAME: <name>.ovpn (all protocols), <name>-udp.ovpn, <name>-tcp.ovpn
ovpn_build_profile() { # ovpn_build_profile NAME
    local name="$1" ip up tp remotes="" f
    ip="$(get_public_ip)"; up="$(ovpn_port_of udp)"; tp="$(ovpn_port_of tcp)"
    mkdir -p "$OVPN_CLIENTS"
    _ovpn_profile() { # file remote-lines
        cat > "$1" <<EOF
client
dev tun
$2
resolv-retry infinite
connect-retry 2
connect-timeout 10
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
verb 3
<ca>
$(cat "$OVPN_DIR/ca.crt")
</ca>
<cert>
$(openssl x509 -in "$OVPN_PKI/pki/issued/$name.crt")
</cert>
<key>
$(cat "$OVPN_PKI/pki/private/$name.key")
</key>
<tls-crypt>
$(cat "$OVPN_DIR/tls-crypt.key")
</tls-crypt>
EOF
        chmod 600 "$1"
    }
    [ -n "$up" ] && { _ovpn_profile "$OVPN_CLIENTS/$name-udp.ovpn" "proto udp
remote $ip $up"; remotes="remote $ip $up udp
"; }
    [ -n "$tp" ] && { _ovpn_profile "$OVPN_CLIENTS/$name-tcp.ovpn" "proto tcp
remote $ip $tp"; remotes="${remotes}remote $ip $tp tcp
"; }
    if [ -n "$up" ] && [ -n "$tp" ]; then
        _ovpn_profile "$OVPN_CLIENTS/$name.ovpn" "${remotes%$'\n'}"
    else
        f="$OVPN_CLIENTS/$name-${up:+udp}${tp:+tcp}.ovpn"; cp "$f" "$OVPN_CLIENTS/$name.ovpn"
    fi
    unset -f _ovpn_profile
}

# Rebuild every active client's profiles (after a protocol/port change)
ovpn_regen_profiles() {
    local f n
    for f in "$OVPN_PKI"/pki/issued/*.crt; do
        [ -f "$f" ] || continue
        n="$(basename "$f" .crt)"; [ "$n" = server ] && continue
        grep -q "^R.*/CN=$n\$" "$OVPN_PKI/pki/index.txt" 2>/dev/null && continue
        ovpn_build_profile "$n"
    done
}

ovpn_add_client() { # ovpn_add_client NAME
    local name="$1"
    ovpn_installed || { err "OpenVPN is not installed."; return 1; }
    valid_name "$name" || { err "Invalid name."; return 1; }
    [ -f "$OVPN_PKI/pki/issued/$name.crt" ] && { err "Client '$name' already exists."; return 1; }
    ovpn_easyrsa build-client-full "$name" nopass || { err "Certificate generation failed."; return 1; }
    ovpn_build_profile "$name"
    log_action "openvpn client added: $name"
    ok "Client '$name' created:"
    echo "   $OVPN_CLIENTS/$name.ovpn       (UDP + TCP, auto-fallback)"
    [ -f "$OVPN_CLIENTS/$name-udp.ovpn" ] && echo "   $OVPN_CLIENTS/$name-udp.ovpn   (UDP only)"
    [ -f "$OVPN_CLIENTS/$name-tcp.ovpn" ] && echo "   $OVPN_CLIENTS/$name-tcp.ovpn   (TCP only)"
}

ovpn_del_client() {
    local name="$1"
    [ -f "$OVPN_PKI/pki/issued/$name.crt" ] || { err "Client '$name' not found."; return 1; }
    ovpn_easyrsa revoke "$name" && ovpn_easyrsa gen-crl || { err "Revocation failed."; return 1; }
    cp "$OVPN_PKI/pki/crl.pem" "$OVPN_DIR/crl.pem"; chmod 644 "$OVPN_DIR/crl.pem"
    rm -f "$OVPN_CLIENTS/$name.ovpn" "$OVPN_CLIENTS/$name-udp.ovpn" "$OVPN_CLIENTS/$name-tcp.ovpn"
    log_action "openvpn client revoked: $name"
    ok "Client '$name' revoked"
}

ovpn_list_clients() {
    [ -d "$OVPN_PKI/pki/issued" ] || { echo "No clients."; return; }
    local found=0 f n
    for f in "$OVPN_PKI"/pki/issued/*.crt; do
        n="$(basename "$f" .crt)"; [ "$n" = server ] && continue
        found=1
        grep -q "^R.*/CN=$n\$" "$OVPN_PKI/pki/index.txt" 2>/dev/null && echo "  ✖ $n (revoked)" || echo "  ✔ $n"
    done
    [ $found -eq 0 ] && echo "No clients."
    return 0
}

ovpn_menu() {
    while true; do
        menu_header "🔒 OpenVPN   UDP: $(ovpn_state_line udp)   TCP: $(ovpn_state_line tcp)"
        echo "  1) Install / add missing protocol (UDP + TCP)"
        echo "  2) Add client (.ovpn)"
        echo "  3) Revoke client"
        echo "  4) List clients"
        echo "  5) Connected clients"
        echo "  6) Restart"
        echo "  7) Uninstall"
        echo "  0) Back"
        echo -e "$LINE"
        case "$(ask "Choose" "")" in
            1) ovpn_install; pause ;;
            2) ovpn_add_client "$(ask "Client name" "")"; pause ;;
            3) ovpn_list_clients; ovpn_del_client "$(ask "Client to revoke" "")"; pause ;;
            4) ovpn_list_clients; echo "Profiles are stored in $OVPN_CLIENTS"; pause ;;
            5) cat /var/log/openvpn-status-server*.log 2>/dev/null | grep -E "^CLIENT_LIST" | cut -d, -f2,3,5,6 | grep . || echo "None"; pause ;;
            6) ovpn_restart_all; pause ;;
            7) if confirm "Remove OpenVPN and all certificates?" n; then
                   local _s; mapfile -t _s < <(ovpn_svcs)
                   systemctl disable --now "${_s[@]}" "$OVPN_NAT_SVC" >/dev/null 2>&1
                   rm -rf "$OVPN_DIR" "$OVPN_PKI" "$OVPN_CLIENTS" "$OVPN_UNIT_DIR/$OVPN_NAT_SVC.service"
                   systemctl daemon-reload; ok "OpenVPN removed"
               fi; pause ;;
            0|"") return ;;
        esac
    done
}
