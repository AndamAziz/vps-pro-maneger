#!/usr/bin/env bash
#==============================================================================
# Hysteria 2 (QUIC / UDP) - multi-user (userpass), shares users.json with Xray
#==============================================================================

HY2_BIN="/usr/local/bin/hysteria"
HY2_DIR="/etc/hysteria"
HY2_CONF="$HY2_DIR/config.yaml"
HY2_SVC="hysteria-server"

hy2_installed() { [ -x "$HY2_BIN" ]; }

hy2_install() {
    require_root
    need_cmd curl; need_cmd openssl
    local port domain obfs=""
    port="$(ask_port "Hysteria2 (UDP)" 443 udp)" || return 1
    domain="$(ask "Domain for automatic Let's Encrypt (empty = self-signed)" "$(setting_get domain)")"
    if confirm "Enable Salamander obfuscation (helps against QUIC blocking)?" n; then obfs="$(rand_str 16)"; fi

    info "Installing Hysteria 2 (official installer)..."
    local script
    script="$(curl -fsSL https://get.hy2.sh/)" || { err "Cannot download the Hysteria installer."; return 1; }
    bash -c "$script" >/dev/null 2>&1 || { err "Hysteria installation failed."; return 1; }
    hy2_installed || { err "Hysteria binary not found."; return 1; }

    mkdir -p "$HY2_DIR"
    setting_set hy2_port "$port"; setting_set hy2_domain "$domain"; setting_set hy2_obfs "$obfs"
    if [ -z "$domain" ]; then
        openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 3650 \
            -subj "/CN=www.bing.com" -keyout "$HY2_DIR/server.key" -out "$HY2_DIR/server.crt" >/dev/null 2>&1
        chown hysteria:hysteria "$HY2_DIR/server.key" "$HY2_DIR/server.crt" 2>/dev/null || chmod 644 "$HY2_DIR/server."*
    else
        fw_allow 80 tcp
    fi
    fw_allow "$port" udp
    systemctl enable "$HY2_SVC" >/dev/null 2>&1
    hy2_apply && ok "Hysteria 2 installed on UDP/$port"
    log_action "hysteria2 installed"
}

hy2_apply() {
    hy2_installed || return 0
    local port domain obfs tls_block
    port="$(setting_get hy2_port)"; port="${port:-443}"
    domain="$(setting_get hy2_domain)"; obfs="$(setting_get hy2_obfs)"
    if [ -n "$domain" ]; then
        tls_block="acme:
  domains:
    - $domain
  email: admin@$domain"
    else
        tls_block="tls:
  cert: $HY2_DIR/server.crt
  key: $HY2_DIR/server.key"
    fi
    {
        echo "listen: :$port"
        echo "$tls_block"
        echo "auth:"
        echo "  type: userpass"
        echo "  userpass:"
        local rows
        rows="$(users_active | jq -r '.[] | "    \(.name): \(.password)"')"
        if [ -z "$rows" ]; then echo "    placeholder: $(rand_str 24)"; else echo "$rows"; fi
        if [ -n "$obfs" ]; then
            echo "obfs:"; echo "  type: salamander"; echo "  salamander:"; echo "    password: $obfs"
        fi
        echo "masquerade:"
        echo "  type: proxy"
        echo "  proxy:"
        echo "    url: https://www.bing.com/"
        echo "    rewriteHost: true"
    } > "$HY2_CONF"
    chmod 640 "$HY2_CONF"; chown root:hysteria "$HY2_CONF" 2>/dev/null || true
    systemctl restart "$HY2_SVC" && ok "Hysteria 2 configuration applied" || { err "Hysteria failed to start (journalctl -u $HY2_SVC -n 30)"; return 1; }
}

# hy2_user_link NAME
hy2_user_link() {
    hy2_installed || return 0
    local name="$1" pw port domain obfs ip q=""
    pw="$(jq -r --arg n "$name" '.[]|select(.name==$n)|.password' "$USERS_DB")"
    [ -n "$pw" ] || return 1
    port="$(setting_get hy2_port)"; domain="$(setting_get hy2_domain)"; obfs="$(setting_get hy2_obfs)"
    ip="$(get_public_ip)"
    if [ -z "$domain" ]; then q="insecure=1&sni=www.bing.com"; else q="sni=$domain"; fi
    [ -n "$obfs" ] && q="${q}&obfs=salamander&obfs-password=$obfs"
    echo "hysteria2://$(urlenc "$name"):$(urlenc "$pw")@${domain:-$ip}:${port}/?${q}#$(urlenc "${name}-hy2")"
}

hy2_menu() {
    while true; do
        menu_header "⚡ Hysteria 2  (QUIC/UDP)   [$(svc_state "$HY2_SVC")]"
        echo "  1) Install Hysteria 2"
        echo "  2) Apply config / restart"
        echo "  3) View logs"
        echo "  4) Uninstall"
        echo "  0) Back"
        echo -e "$LINE"
        case "$(ask "Choose" "")" in
            1) hy2_install; pause ;;
            2) hy2_apply; pause ;;
            3) journalctl -u "$HY2_SVC" -n 60 --no-pager; pause ;;
            4) if confirm "Remove Hysteria 2?" n; then
                   local s; s="$(curl -fsSL https://get.hy2.sh/)" && bash -c "$s" --remove >/dev/null 2>&1
                   rm -rf "$HY2_DIR"; ok "Removed"
               fi; pause ;;
            0|"") return ;;
        esac
    done
}
