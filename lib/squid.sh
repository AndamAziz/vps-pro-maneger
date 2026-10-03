#!/usr/bin/env bash
#==============================================================================
# Squid HTTP/HTTPS proxy - open proxy (no username / password)
#   Optional: restrict to your own IP(s) with `vpsmanager squid ip <IP...>`
#==============================================================================

SQUID_CONF="/etc/squid/squid.conf"

squid_installed() { [ -f "$SQUID_CONF" ] && command -v squid >/dev/null 2>&1; }

squid_port() { local p; p="$(setting_get squid_port)"; echo "${p:-3128}"; }

# Allowed client IPs ('' = everyone)
squid_allowed() { setting_get squid_allow_ips; }

squid_write_config() { # squid_write_config PORT
    local port="$1" ips access
    ips="$(squid_allowed)"
    if [ -n "$ips" ]; then
        # localhost and the server's own address are always allowed (self-test)
        access="acl allowed_ips src $ips 127.0.0.1/32 ::1/128 $(get_public_ip)/32
http_access allow allowed_ips"
    else
        access="http_access allow all"
    fi
    [ -f "$SQUID_CONF" ] && [ ! -f "$SQUID_CONF.vpsm-orig" ] && cp "$SQUID_CONF" "$SQUID_CONF.vpsm-orig"
    cat > "$SQUID_CONF" <<CONF
# Managed by VPS Manager Pro - open proxy (no authentication)
http_port $port
visible_hostname vpsmanager
max_filedescriptors 65535

# Abuse protection (also applies when the proxy is open to everyone)
http_access deny manager
# never let clients reach this server or private networks (SSH, Xray API, panels ...)
acl private_dst dst 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 0.0.0.0/8 100.64.0.0/10
acl private_dst6 dst ::1/128 fc00::/7 fe80::/10
http_access deny private_dst
http_access deny private_dst6
# no outgoing mail / NetBIOS / telnet (spam and scanning abuse gets VPSs suspended)
acl abuse_ports port 25 465 587 23 135 137 138 139 445
http_access deny abuse_ports
# at most 80 simultaneous connections per client address
acl too_many_conns maxconn 80
http_access deny too_many_conns
$access
http_access deny all

# Free idle sockets quickly (small VPS)
client_idle_pconn_timeout 20 seconds
pconn_timeout 30 seconds
request_timeout 30 seconds
connect_timeout 20 seconds
half_closed_clients off
cache_mem 8 MB

# Privacy / speed
forwarded_for delete
via off
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
dns_nameservers 1.1.1.1 8.8.8.8
cache deny all
access_log none
CONF
}

# Keep ufw in step with the access mode: in IP mode only those IPs may even reach the port.
squid_fw_sync() { # squid_fw_sync PORT
    fw_active || return 0
    local port="$1" ips ip oldport
    ips="$(squid_allowed)"
    oldport="$(setting_get squid_fw_port)"; oldport="${oldport:-$port}"
    for ip in $(setting_get squid_fw_ips); do
        ufw delete allow from "$ip" to any port "$oldport" proto tcp >/dev/null 2>&1
    done
    setting_del squid_fw_ips
    if [ -z "$ips" ]; then
        ufw allow "$port/tcp" >/dev/null 2>&1
    else
        ufw delete allow "$port/tcp" >/dev/null 2>&1
        for ip in $ips; do ufw allow from "$ip" to any port "$port" proto tcp >/dev/null 2>&1; done
        setting_set squid_fw_ips "$ips"
        setting_set squid_fw_port "$port"
    fi
}

# Validate, restart and roll back on failure
squid_apply() {
    squid_installed || { err "Squid is not installed."; return 1; }
    local port="${1:-$(squid_port)}"
    cp "$SQUID_CONF" "$SQUID_CONF.prev" 2>/dev/null
    squid_write_config "$port"
    if squid -k parse >/dev/null 2>&1 && systemctl restart squid 2>/dev/null; then
        sleep 1
        if svc_active squid; then
            setting_set squid_port "$port"
            squid_fw_sync "$port"
            ok "Squid is running on TCP/$port"
            return 0
        fi
    fi
    err "Squid failed to start with port $port."
    squid -k parse 2>&1 | grep -E "ERROR|FATAL" | head -3
    [ -f "$SQUID_CONF.prev" ] && cp "$SQUID_CONF.prev" "$SQUID_CONF" && systemctl restart squid 2>/dev/null
    return 1
}

# shellcheck disable=SC2120  # called with an argument from the vpsmanager CLI
squid_install() { # squid_install [PORT]
    require_root
    squid_installed && { warn "Squid is already installed - applying the latest configuration."; squid_apply; return; }
    local port="${1:-}"
    [ -n "$port" ] || port="$(ask_port "Squid proxy" 3128)" || return 1
    valid_port "$port" || { err "Invalid port."; return 1; }
    port_in_use "$port" tcp && { err "Port $port is already in use."; return 1; }
    sys_tune_conntrack
    info "Installing Squid..."
    pkg_install squid || return 1
    systemctl enable squid >/dev/null 2>&1
    squid_apply "$port" || return 1
    echo "  Proxy: $(get_public_ip):$port   (no username / password)"
    log_action "squid installed on $port"
}

# shellcheck disable=SC2120
squid_change_port() { # squid_change_port [PORT]
    squid_installed || { err "Squid is not installed."; return 1; }
    local old new="${1:-}"
    old="$(squid_port)"
    [ -n "$new" ] || new="$(ask "New port" 3128)"
    valid_port "$new" || { err "Invalid port."; return 1; }
    if [ "$new" != "$old" ] && port_in_use "$new" tcp; then
        err "Port $new is already used by another service:"
        ss -ltnp 2>/dev/null | awk -v p=":$new\$" '$4 ~ p {print "   " $0}'
        return 1
    fi
    if squid_apply "$new"; then
        [ "$new" != "$old" ] && fw_deny "$old" tcp
        echo "  Proxy: $(get_public_ip):$new"
        return 0
    fi
    return 1
}

# squid_set_ips IP...   (no arguments or 'open' = allow everyone)
squid_set_ips() {
    squid_installed || { err "Squid is not installed."; return 1; }
    local ip
    if [ $# -eq 0 ] || [ "$1" = open ]; then
        setting_del squid_allow_ips
        squid_apply && warn "Open to everyone."
        return
    fi
    for ip in "$@"; do
        [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$ ]] || { err "Invalid IP: $ip"; return 1; }
    done
    setting_set squid_allow_ips "$*"
    squid_apply && ok "Only these IPs can use the proxy: $*"
}

# Real test: through localhost and through the public address
squid_test() {
    squid_installed || { err "Squid is not installed."; return 1; }
    local port ip r1 r2
    port="$(squid_port)"; ip="$(get_public_ip)"
    echo -e "${BOLD}Squid self-test${NC}"
    if svc_active squid; then ok "service is running"; else err "service is NOT running (journalctl -u squid -n 30)"; return 1; fi
    if port_in_use "$port" tcp; then ok "listening on TCP/$port"; else err "nothing listens on TCP/$port"; fi
    if r1="$(curl -fsS -m 10 -x "http://127.0.0.1:$port" https://ifconfig.me 2>&1)"; then
        ok "HTTPS through 127.0.0.1:$port → $r1"
    else err "HTTPS via localhost failed: $r1"; fi
    if r2="$(curl -fsS -m 10 -x "http://$ip:$port" http://ifconfig.me 2>&1)"; then
        ok "HTTP  through $ip:$port → $r2"
    else err "via public IP failed: $r2"; fi
    if fw_active; then
        if ufw status | grep -qE "^$port(/tcp)? +ALLOW"; then ok "ufw allows $port/tcp"
        else warn "ufw is active but $port/tcp is not allowed - run: ufw allow $port/tcp"; fi
    fi
    echo -e "${DIM}If the tests pass but your phone/PC cannot connect, open TCP/$port in your hosting provider's firewall panel.${NC}"
}

squid_menu() {
    while true; do
        if squid_installed; then
            local acc="everyone"; [ -n "$(squid_allowed)" ] && acc="only: $(squid_allowed)"
            menu_header "🌐 Squid HTTP Proxy   [$(svc_state squid)]   port $(squid_port)   access: $acc"
        else
            menu_header "🌐 Squid HTTP Proxy   [not installed]"
        fi
        echo "  1) Install Squid (no username / password)"
        echo "  2) Restart / re-apply configuration"
        echo "  3) Change port"
        echo "  4) Show open ports"
        echo "  5) Test proxy"
        echo "  6) Restrict to my IP(s) / open to everyone"
        echo "  7) View logs"
        echo "  8) Uninstall"
        echo "  0) Back"
        echo -e "$LINE"
        case "$(ask "Choose" "")" in
            1) squid_install; pause ;;
            2) squid_apply; pause ;;
            3) squid_change_port; pause ;;
            4) sys_ports; pause ;;
            5) squid_test; pause ;;
            6) echo "  1) Only my IP(s)   2) Everyone"
               case "$(ask "Choose" "")" in
                   1) read -ra _ips <<<"$(ask "Allowed IP(s), space separated" "${SSH_CLIENT%% *}")"; squid_set_ips "${_ips[@]}" ;;
                   2) squid_set_ips open ;;
               esac; pause ;;
            7) journalctl -u squid -n 60 --no-pager; pause ;;
            8) if confirm "Remove Squid?" n; then
                   systemctl disable --now squid >/dev/null 2>&1
                   DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq squid >/dev/null 2>&1
                   setting_del squid_port; setting_del squid_allow_ips; ok "Squid removed"
               fi; pause ;;
            0|"") return ;;
        esac
    done
}
