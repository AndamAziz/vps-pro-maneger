#!/usr/bin/env bash
#==============================================================================
# OpenVPN (easy-rsa 3, ECDSA, tls-crypt, AES-256-GCM)
#==============================================================================

OVPN_DIR="/etc/openvpn/server"
OVPN_PKI="/etc/openvpn/easy-rsa"
OVPN_CLIENTS="$VPSM_ETC/openvpn"
OVPN_SVC="openvpn-server@server"
OVPN_NAT_SVC="vpsm-openvpn-nat"

ovpn_installed() { [ -f "$OVPN_DIR/server.conf" ]; }

ovpn_easyrsa() { (cd "$OVPN_PKI" && EASYRSA_BATCH=1 EASYRSA_ALGO=ec EASYRSA_CURVE=prime256v1 ./easyrsa "$@" >/dev/null 2>&1); }

ovpn_install() {
    require_root
    ovpn_installed && { warn "OpenVPN is already installed."; return 0; }
    local port proto iface
    proto="$(ask "Protocol (udp/tcp)" "udp")"; [[ "$proto" =~ ^(udp|tcp)$ ]] || proto=udp
    port="$(ask_port "OpenVPN" "$([ "$proto" = tcp ] && echo 443 || echo 1194)" "$proto")" || return 1
    iface="$(default_iface)"
    [ -n "$iface" ] || { err "Cannot detect the default network interface."; return 1; }

    info "Installing OpenVPN + easy-rsa..."
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

    cat > "$OVPN_DIR/server.conf" <<EOF
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
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /var/lib/openvpn/ipp.txt
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
status /var/log/openvpn-status.log 10
verb 3
$([ "$proto" = udp ] && echo "explicit-exit-notify 1")
EOF
    mkdir -p /var/lib/openvpn

    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-vpsm-forward.conf
    sysctl -p /etc/sysctl.d/99-vpsm-forward.conf >/dev/null 2>&1

    cat > "/etc/systemd/system/$OVPN_NAT_SVC.service" <<EOF
[Unit]
Description=NAT rules for OpenVPN
After=network-online.target
Before=openvpn-server@server.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $iface -j MASQUERADE
ExecStart=/sbin/iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
ExecStart=/sbin/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=/sbin/iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $iface -j MASQUERADE
ExecStop=/sbin/iptables -D FORWARD -s 10.8.0.0/24 -j ACCEPT
ExecStop=/sbin/iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    setting_set ovpn_port "$port"; setting_set ovpn_proto "$proto"
    fw_allow "$port" "$proto"
    systemctl enable --now "$OVPN_NAT_SVC" "$OVPN_SVC" >/dev/null 2>&1
    sleep 1
    svc_active "$OVPN_SVC" && ok "OpenVPN installed on ${proto^^}/$port" \
        || { err "OpenVPN failed to start (journalctl -u $OVPN_SVC -n 30)"; return 1; }
    log_action "openvpn installed"
}

ovpn_add_client() { # ovpn_add_client NAME
    local name="$1" ip port proto out
    ovpn_installed || { err "OpenVPN is not installed."; return 1; }
    valid_name "$name" || { err "Invalid name."; return 1; }
    [ -f "$OVPN_PKI/pki/issued/$name.crt" ] && { err "Client '$name' already exists."; return 1; }
    ovpn_easyrsa build-client-full "$name" nopass || { err "Certificate generation failed."; return 1; }
    ip="$(get_public_ip)"; port="$(setting_get ovpn_port)"; proto="$(setting_get ovpn_proto)"
    mkdir -p "$OVPN_CLIENTS"; out="$OVPN_CLIENTS/$name.ovpn"
    cat > "$out" <<EOF
client
dev tun
proto $proto
remote $ip $port
resolv-retry infinite
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
    chmod 600 "$out"
    log_action "openvpn client added: $name"
    ok "Client '$name' created → $out"
}

ovpn_del_client() {
    local name="$1"
    [ -f "$OVPN_PKI/pki/issued/$name.crt" ] || { err "Client '$name' not found."; return 1; }
    ovpn_easyrsa revoke "$name" && ovpn_easyrsa gen-crl || { err "Revocation failed."; return 1; }
    cp "$OVPN_PKI/pki/crl.pem" "$OVPN_DIR/crl.pem"; chmod 644 "$OVPN_DIR/crl.pem"
    rm -f "$OVPN_CLIENTS/$name.ovpn"
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
        menu_header "🔒 OpenVPN   [$(svc_state "$OVPN_SVC")]"
        echo "  1) Install OpenVPN"
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
            5) grep -E "^CLIENT_LIST" /var/log/openvpn-status.log 2>/dev/null | cut -d, -f2,3,5,6 || echo "None"; pause ;;
            6) svc_restart "$OVPN_SVC"; pause ;;
            7) if confirm "Remove OpenVPN and all certificates?" n; then
                   systemctl disable --now "$OVPN_SVC" "$OVPN_NAT_SVC" >/dev/null 2>&1
                   rm -rf "$OVPN_DIR" "$OVPN_PKI" "$OVPN_CLIENTS" "/etc/systemd/system/$OVPN_NAT_SVC.service"
                   systemctl daemon-reload; ok "OpenVPN removed"
               fi; pause ;;
            0|"") return ;;
        esac
    done
}
