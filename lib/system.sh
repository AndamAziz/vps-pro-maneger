#!/usr/bin/env bash
#==============================================================================
# System: status, BBR, firewall, fail2ban, swap, updates, backup/restore
#==============================================================================

sys_info() {
    detect_os
    local mem disk load
    mem="$(free -m | awk '/^Mem:/ {printf "%d/%d MB", $3, $2}')"
    disk="$(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")"}')"
    load="$(cut -d' ' -f1-3 /proc/loadavg)"
    echo -e "  OS        : $OS_NAME ($OS_ARCH)"
    echo -e "  Kernel    : $(uname -r)"
    echo -e "  Public IP : $(get_public_ip)"
    echo -e "  Uptime    : $(uptime -p 2>/dev/null)"
    echo -e "  Load      : $load   CPU cores: $(nproc)"
    echo -e "  Memory    : $mem"
    echo -e "  Disk (/)  : $disk"
    echo -e "  TCP CC    : $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    local ct cm
    ct="$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)"; cm="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"
    if [ -n "$ct" ] && [ -n "$cm" ]; then
        echo -e "  Conntrack : $ct / $cm$([ $((ct * 100 / cm)) -ge 80 ] && echo -e "  ${RED}(almost full - run: vpsmanager tune)${NC}")"
    fi
}

# List every listening port (TCP + UDP) with the owning process
sys_ports() {
    local rows
    rows="$(ss -H -lntup 2>/dev/null | awk '{
        proto=$1; n=split($5, a, ":"); port=a[n]; addr=$5; sub(":" port "$", "", addr);
        proc="-"; if (match($0, /users:\(\("[^"]+"/)) { proc=substr($0, RSTART+9, RLENGTH-10) }
        scope=(addr ~ /^(127\.|\[::1\])/) ? "local-only" : "public";
        print proto "\t" port "\t" proc "\t" scope }' | sort -t$'\t' -k1,1 -k2,2n -u)"
    [ -n "$rows" ] || { echo "No listening ports found."; return; }
    printf "${BOLD}%-6s %-8s %-18s %s${NC}\n" "PROTO" "PORT" "PROCESS" "ACCESS"
    while IFS=$'\t' read -r proto port proc scope; do
        local col="$GREEN"; [ "$scope" = local-only ] && col="$DIM"
        printf "%-6s %-8s %-18s ${col}%s${NC}\n" "$proto" "$port" "$proc" "$scope"
    done <<<"$rows"
    echo ""
    echo -e "Open to the internet: ${BOLD}$(awk -F'\t' '$4=="public" && $1=="tcp"' <<<"$rows" | wc -l) TCP${NC} + ${BOLD}$(awk -F'\t' '$4=="public" && $1=="udp"' <<<"$rows" | wc -l) UDP${NC} port(s)"
    if fw_active; then
        echo -e "Firewall (ufw): ${GREEN}active${NC} - allowed rules:"
        ufw status | awk '/ALLOW/ && !/\(v6\)/ {print "   " $1}' | sort -un | tr '\n' ' '; echo
    else
        echo -e "Firewall (ufw): ${YELLOW}inactive${NC} - every listening public port is reachable (unless your hosting provider blocks it)."
    fi
}

sys_status() {
    echo -e "${BOLD}Services${NC}"
    printf "  %-22s %s\n" "SSH"            "$(svc_state "$(ssh_service)")"
    printf "  %-22s %s\n" "Xray"           "$(svc_state xray)"
    printf "  %-22s %s\n" "Hysteria 2"     "$(svc_state hysteria-server)"
    printf "  %-22s %s\n" "WireGuard"      "$(svc_state wg-quick@wg0)"
    printf "  %-22s %s\n" "OpenVPN"        "$(svc_state openvpn-server@server)"
    printf "  %-22s %s\n" "Squid"          "$(svc_state squid)"
    printf "  %-22s %s\n" "BadVPN UDPGW"   "$(svc_state badvpn-udpgw)"
    printf "  %-22s %s\n" "Telegram bot"   "$(svc_state vpsm-bot)"
    printf "  %-22s %s\n" "Fail2ban"       "$(svc_state fail2ban)"
    printf "  %-22s %s\n" "Firewall (ufw)" "$(fw_active && echo -e "${GREEN}active${NC}" || echo -e "${DIM}inactive${NC}")"
}

sys_enable_bbr() {
    require_root
    if [ "$(sysctl -n net.ipv4.tcp_congestion_control)" = bbr ]; then ok "BBR is already active"; return 0; fi
    modprobe tcp_bbr 2>/dev/null
    cat > /etc/sysctl.d/99-vpsm-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl --system >/dev/null 2>&1
    [ "$(sysctl -n net.ipv4.tcp_congestion_control)" = bbr ] && ok "BBR enabled" || warn "Kernel does not support BBR"
}

# Raise the connection-tracking table. The kernel default (often ~7k-65k) fills up on proxy
# servers and then silently drops packets ("nf_conntrack: table full, dropping packet").
sys_tune_conntrack() {
    [ "$EUID" -eq 0 ] || return 0
    modprobe nf_conntrack 2>/dev/null || return 0
    echo nf_conntrack > /etc/modules-load.d/vpsm-conntrack.conf
    echo 'options nf_conntrack hashsize=65536' > /etc/modprobe.d/vpsm-conntrack.conf
    cat > /etc/sysctl.d/99-vpsm-conntrack.conf <<'CT'
net.netfilter.nf_conntrack_max=262144
net.netfilter.nf_conntrack_tcp_timeout_established=7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait=30
net.netfilter.nf_conntrack_tcp_timeout_close_wait=30
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=30
CT
    [ -w /sys/module/nf_conntrack/parameters/hashsize ] && echo 65536 > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null
    sysctl --system >/dev/null 2>&1
    return 0
}

sys_tune() {
    require_root
    cat > /etc/sysctl.d/99-vpsm-tune.conf <<'EOF'
fs.file-max=1048576
net.core.somaxconn=4096
net.core.netdev_max_backlog=16384
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=10240 65535
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
    sysctl --system >/dev/null 2>&1
    sys_tune_conntrack
    cat > /etc/security/limits.d/99-vpsm.conf <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
    ok "Kernel / network limits tuned"
}

sys_swap() {
    require_root
    swapon --show | grep -q . && { warn "Swap already exists:"; swapon --show; return 0; }
    local size; size="$(ask "Swap size in GB" 1)"
    [[ "$size" =~ ^[0-9]+$ ]] || { err "Invalid size"; return 1; }
    fallocate -l "${size}G" /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile \
        && { grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab; ok "${size}G swap enabled"; } \
        || err "Could not create swap"
}

#---- firewall ------------------------------------------------------------------------

fw_enable() {
    require_root
    pkg_install ufw || return 1
    local p
    for p in $(ssh_current_ports); do ufw allow "$p/tcp" >/dev/null; done
    # open everything the manager has configured
    [ -s "$XRAY_INB" ] && jq -r '.[] | . as $i | [$i.port, ($i.plain_port // empty)] | .[] | "\(.) \($i.type)"' "$XRAY_INB" | while read -r port type; do
        [ "$type" = ss2022 ] && ufw allow "$port" >/dev/null || ufw allow "$port/tcp" >/dev/null; done
    for kv in hy2_port:udp wg_port:udp ovpn_port:"$(setting_get ovpn_proto)" squid_port:tcp; do
        p="$(setting_get "${kv%%:*}")"; [ -n "$p" ] && ufw allow "$p/${kv#*:}" >/dev/null 2>&1
    done
    ufw allow 80/tcp >/dev/null
    ufw default deny incoming >/dev/null; ufw default allow outgoing >/dev/null
    ufw --force enable >/dev/null && ok "Firewall enabled (SSH + configured services allowed)"
}

fw_menu() {
    while true; do
        menu_header "🧱 Firewall (ufw)"
        echo "  1) Enable firewall (auto-opens SSH + installed services)"
        echo "  2) Disable firewall"
        echo "  3) Allow a port"
        echo "  4) Delete an allow rule"
        echo "  5) Show rules"
        echo "  0) Back"
        echo -e "$LINE"
        case "$(ask "Choose" "")" in
            1) fw_enable; pause ;;
            2) ufw --force disable; pause ;;
            3) local p pr; p="$(ask "Port" "")"; pr="$(ask "Protocol (tcp/udp/both)" tcp)"
               valid_port "$p" && { [ "$pr" = both ] && ufw allow "$p" || ufw allow "$p/$pr"; }; pause ;;
            4) ufw status numbered; ufw delete "$(ask "Rule number" "")"; pause ;;
            5) ufw status verbose; pause ;;
            0|"") return ;;
        esac
    done
}

sys_fail2ban() {
    require_root
    pkg_install fail2ban || return 1
    cat > /etc/fail2ban/jail.d/vpsm.local <<EOF
[sshd]
enabled = true
port = $(ssh_current_ports | tr ' ' ',' | sed 's/,$//')
maxretry = 5
findtime = 10m
bantime = 1h
backend = systemd
EOF
    systemctl enable --now fail2ban >/dev/null 2>&1; systemctl restart fail2ban
    ok "Fail2ban active for SSH (5 failures → 1 hour ban)"
}

sys_update_os() {
    require_root
    info "Updating packages..."
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get -y -qq upgrade && ok "System updated"
    [ -f /var/run/reboot-required ] && warn "A reboot is recommended."
    return 0
}

sys_cleanup() {
    apt-get -y -qq autoremove >/dev/null 2>&1; apt-get -y -qq clean >/dev/null 2>&1
    journalctl --vacuum-time=7d >/dev/null 2>&1
    ok "Cleanup finished"
}

#---- backup / restore ----------------------------------------------------------------------

sys_backup() {
    require_root
    mkdir -p "$VPSM_BACKUP_DIR"
    local out paths=("$VPSM_ETC")
    out="$VPSM_BACKUP_DIR/vpsm-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    for p in /usr/local/etc/xray /etc/hysteria /etc/wireguard /etc/openvpn/easy-rsa /etc/openvpn/server /etc/squid/passwd /etc/letsencrypt; do
        [ -e "$p" ] && paths+=("$p")
    done
    tar -czf "$out" "${paths[@]}" 2>/dev/null && chmod 600 "$out" && ok "Backup saved: $out"
    ls -1t "$VPSM_BACKUP_DIR"/vpsm-backup-*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm -f   # keep last 10
    echo "$out"
}

sys_restore() { # sys_restore FILE
    require_root
    [ -f "$1" ] || { err "File not found: $1"; return 1; }
    confirm "Restoring overwrites current configuration. Continue?" n || return 1
    tar -xzf "$1" -C / && ok "Restored. Re-applying configs..." && { apply_all; systemctl restart wg-quick@wg0 openvpn-server@server squid 2>/dev/null; true; }
}

sys_self_update() {
    require_root
    info "Checking for updates..."
    if [ -d "$VPSM_HOME/.git" ]; then
        git -C "$VPSM_HOME" fetch -q origin && git -C "$VPSM_HOME" reset -q --hard "origin/$(git -C "$VPSM_HOME" rev-parse --abbrev-ref HEAD)" \
            && ok "Updated to $(git -C "$VPSM_HOME" rev-parse --short HEAD)" || { err "git update failed"; return 1; }
    else
        local tmp; tmp="$(mktemp -d)"
        curl -fsSL "https://github.com/${VPSM_REPO}/archive/refs/heads/main.tar.gz" | tar -xz -C "$tmp" --strip-components=1 \
            && cp -a "$tmp"/. "$VPSM_HOME"/ && ok "Updated" || { err "Download failed"; rm -rf "$tmp"; return 1; }
        rm -rf "$tmp"
    fi
    chmod +x "$VPSM_HOME/vpsmanager"
    [ -f "$VPSM_HOME/bot/requirements.txt" ] && [ -d "$VPSM_HOME/venv" ] && "$VPSM_HOME/venv/bin/pip" install -q -r "$VPSM_HOME/bot/requirements.txt" 2>/dev/null
    svc_active vpsm-bot && systemctl restart vpsm-bot
    log_action "self-update"
}

#---- one-click ------------------------------------------------------------------------------

quick_setup() {
    require_root
    info "One-click setup: BBR + Xray (Reality + VMess-WS) + Hysteria2 + first user"
    sys_enable_bbr
    xray_installed || xray_install || return 1
    xray_inbound_exists reality-443 || xray_add_inbound reality 443 "" "www.microsoft.com"
    xray_inbound_exists vmess-ws-8080 || xray_add_inbound vmess-ws 8080 "" "/$(rand_str 8)"
    local first; first="${1:-admin}"
    user_exists "$first" || user_add "$first" 0
    apply_all
    echo -e "$LINE"; user_show "$first"
}

#---- menu ------------------------------------------------------------------------------------

system_menu() {
    while true; do
        menu_header "⚙️  System"
        echo "  1) Server info & service status    7) Update OS packages"
        echo "  13) Show open ports"
        echo "  2) Enable BBR                      8) Clean up"
        echo "  3) Tune network / limits           9) Backup configuration"
        echo "  4) Firewall (ufw)                 10) Restore backup"
        echo "  5) Install Fail2ban               11) Update VPS Manager"
        echo "  6) Create swap file               12) Reboot server"
        echo "  0) Back"
        echo -e "$LINE"
        case "$(ask "Choose" "")" in
            1) sys_info; echo ""; sys_status; pause ;;
            2) sys_enable_bbr; pause ;;
            3) sys_tune; pause ;;
            4) fw_menu ;;
            5) sys_fail2ban; pause ;;
            6) sys_swap; pause ;;
            7) sys_update_os; pause ;;
            8) sys_cleanup; pause ;;
            9) sys_backup >/dev/null; pause ;;
            10) ls -1t "$VPSM_BACKUP_DIR"/*.tar.gz 2>/dev/null; sys_restore "$(ask "Backup file path" "")"; pause ;;
            11) sys_self_update; pause ;;
            12) confirm "Reboot now?" n && reboot ;;
            13) sys_ports; pause ;;
            0|"") return ;;
        esac
    done
}
