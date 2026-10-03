#!/usr/bin/env bash
#==============================================================================
# Squid HTTP/HTTPS proxy with basic authentication
#==============================================================================

SQUID_CONF="/etc/squid/squid.conf"
SQUID_PASSWD="/etc/squid/passwd"

squid_installed() { [ -f "$SQUID_CONF" ] && command -v squid >/dev/null 2>&1; }

squid_auth_helper() {
    local h
    for h in /usr/lib/squid/basic_ncsa_auth /usr/lib64/squid/basic_ncsa_auth; do [ -x "$h" ] && { echo "$h"; return; }; done
    echo /usr/lib/squid/basic_ncsa_auth
}

squid_write_config() { # squid_write_config PORT
    local port="$1"
    [ -f "$SQUID_CONF" ] && [ ! -f "$SQUID_CONF.vpsm-orig" ] && cp "$SQUID_CONF" "$SQUID_CONF.vpsm-orig"
    cat > "$SQUID_CONF" <<EOF
# Managed by VPS Manager Pro
http_port $port
auth_param basic program $(squid_auth_helper) $SQUID_PASSWD
auth_param basic realm Proxy
auth_param basic credentialsttl 2 hours
acl authenticated proxy_auth REQUIRED
acl SSL_ports port 443
acl Safe_ports port 80 21 443 1025-65535
acl CONNECT method CONNECT
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access deny manager
http_access allow authenticated
http_access deny all
forwarded_for delete
via off
request_header_access X-Forwarded-For deny all
dns_v4_first on
cache deny all
access_log /var/log/squid/access.log
EOF
}

squid_install() {
    require_root
    squid_installed && { warn "Squid is already installed."; return 0; }
    local port user pass
    port="$(ask_port "Squid proxy" 3128)" || return 1
    info "Installing Squid..."
    pkg_install squid apache2-utils || return 1
    : > "$SQUID_PASSWD"; chown proxy:proxy "$SQUID_PASSWD" 2>/dev/null; chmod 640 "$SQUID_PASSWD"
    squid_write_config "$port"
    setting_set squid_port "$port"
    fw_allow "$port" tcp
    user="$(ask "First proxy username" "proxy")"; pass="$(rand_str 14)"
    htpasswd -b -B "$SQUID_PASSWD" "$user" "$pass" >/dev/null 2>&1
    systemctl enable squid >/dev/null 2>&1; systemctl restart squid
    svc_active squid && { ok "Squid running on TCP/$port"; echo "  user: $user   password: $pass"; } \
        || { err "Squid failed to start (journalctl -u squid -n 30)"; return 1; }
    log_action "squid installed"
}

squid_add_user() { # squid_add_user NAME [PASSWORD]
    local user="$1" pass="${2:-$(rand_str 14)}"
    squid_installed || { err "Squid is not installed."; return 1; }
    valid_name "$user" || { err "Invalid name."; return 1; }
    htpasswd -b -B "$SQUID_PASSWD" "$user" "$pass" >/dev/null 2>&1 || { err "htpasswd failed"; return 1; }
    systemctl reload squid 2>/dev/null || systemctl restart squid
    ok "Proxy user '$user' set. Password: $pass"
    echo "  http://$user:$pass@$(get_public_ip):$(setting_get squid_port)"
}

squid_del_user() {
    squid_installed || { err "Squid is not installed."; return 1; }
    grep -q "^$1:" "$SQUID_PASSWD" || { err "User '$1' not found."; return 1; }
    htpasswd -D "$SQUID_PASSWD" "$1" >/dev/null 2>&1 && ok "Proxy user '$1' removed"
    systemctl reload squid 2>/dev/null || true
}

squid_change_port() {
    squid_installed || { err "Squid is not installed."; return 1; }
    local old new
    old="$(setting_get squid_port)"; old="${old:-3128}"
    new="$(ask "New port" 3128)"
    valid_port "$new" || { err "Invalid port."; return 1; }
    if [ "$new" != "$old" ] && port_in_use "$new" tcp; then
        err "Port $new is already used by another service:"
        ss -ltnp 2>/dev/null | awk -v p=":$new\$" '$4 ~ p {print "   " $0}'
        return 1
    fi
    cp "$SQUID_CONF" "$SQUID_CONF.prev"
    squid_write_config "$new"
    if squid -k parse >/dev/null 2>&1 && systemctl restart squid && svc_active squid; then
        setting_set squid_port "$new"; fw_allow "$new" tcp
        [ "$new" != "$old" ] && fw_deny "$old" tcp
        ok "Squid now listens on TCP/$new"
    else
        err "Squid failed with port $new - restoring the previous configuration."
        cp "$SQUID_CONF.prev" "$SQUID_CONF"; systemctl restart squid
        return 1
    fi
}

squid_menu() {
    while true; do
        menu_header "🌐 Squid HTTP Proxy   [$(svc_state squid)]"
        echo "  1) Install Squid"
        echo "  2) Add / change proxy user"
        echo "  3) Delete proxy user"
        echo "  4) List proxy users"
        echo "  5) Change port"
        echo "  6) Restart"
        echo "  7) Uninstall"
        echo "  0) Back"
        echo -e "$LINE"
        case "$(ask "Choose" "")" in
            1) squid_install; pause ;;
            2) squid_add_user "$(ask "Username" "")" "$(ask "Password (empty = random)" "")"; pause ;;
            3) squid_del_user "$(ask "Username" "")"; pause ;;
            4) cut -d: -f1 "$SQUID_PASSWD" 2>/dev/null || echo "none"; pause ;;
            5) squid_change_port; pause ;;
            6) svc_restart squid; pause ;;
            7) if confirm "Remove Squid?" n; then
                   systemctl disable --now squid >/dev/null 2>&1
                   DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq squid >/dev/null 2>&1; ok "Squid removed"
               fi; pause ;;
            0|"") return ;;
        esac
    done
}
