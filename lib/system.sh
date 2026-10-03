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
    # xray/squid open short-lived UDP sockets on random ports for proxied UDP traffic (QUIC, calls, games).
    # They are not listeners we configured: hide them, except a real Shadowsocks-2022 inbound port.
    local cfgudp hidden
    cfgudp="$(jq -r '.[]|select(.type=="ss2022")|.port' "$XRAY_INB" 2>/dev/null | tr '\n' ' ')"
    hidden="$(awk -F'\t' -v cfg=" $cfgudp" '$1=="udp" && $4=="public" && ($3=="xray" || $3=="squid") && index(cfg, " " $2 " ")==0' <<<"$rows" | wc -l)"
    rows="$(awk -F'\t' -v cfg=" $cfgudp" '!($1=="udp" && $4=="public" && ($3=="xray" || $3=="squid") && index(cfg, " " $2 " ")==0)' <<<"$rows")"
    printf "${BOLD}%-6s %-8s %-18s %s${NC}\n" "PROTO" "PORT" "PROCESS" "ACCESS"
    # WireGuard is a kernel socket: ss shows no process name for it
    local wgports ifc
    wgports="$(for ifc in $(wg show interfaces 2>/dev/null); do wg show "$ifc" listen-port 2>/dev/null; done)"
    while IFS=$'\t' read -r proto port proc scope; do
        [ "$proc" = "-" ] && [ "$proto" = udp ] && grep -qx "$port" <<<"$wgports" && proc="wireguard"
        local col="$GREEN"; [ "$scope" = local-only ] && col="$DIM"
        printf "%-6s %-8s %-18s ${col}%s${NC}\n" "$proto" "$port" "$proc" "$scope"
    done <<<"$rows"
    [ "${hidden:-0}" -gt 0 ] && echo -e "${DIM}(+${hidden} temporary UDP sockets of xray/squid hidden - proxied UDP traffic, not open ports)${NC}"
    echo ""
    echo -e "Open to the internet: ${BOLD}$(awk -F'\t' '$4=="public" && $1=="tcp"' <<<"$rows" | wc -l) TCP${NC} + ${BOLD}$(awk -F'\t' '$4=="public" && $1=="udp"' <<<"$rows" | wc -l) UDP${NC} port(s)"
    if fw_active; then
        echo -e "Firewall (ufw): ${GREEN}active${NC} - allowed rules:"
        ufw status | awk '/ALLOW/ && !/\(v6\)/ {print $1}' | sort -t/ -k1,1n -k2,2 -u | sed 's/^/   /' | tr '\n' ' '; echo
    else
        echo -e "Firewall (ufw): ${YELLOW}inactive${NC} - every listening public port is reachable (unless your hosting provider blocks it)."
    fi
}

# One-shot diagnostics for "X does not work" reports. Prints no private keys or passwords
# (wg show lists public keys only; configs are not dumped).
# real packet lines in a tcpdump capture (tcpdump prints an empty line when `timeout` stops it)
_cap_count() { grep -cE ' IP6? ' "$1" 2>/dev/null || true; }

# _watch_row LABEL ARRIVED_FILE ANSWERED_FILE
# arrived  = packets/SYNs that reached the NIC (seen BEFORE the firewall)
# answered = what this server sent back (SYN-ACK / UDP reply): means the firewall let it in AND something listens
_watch_row() {
    local label="$1" af="$2" rf="$3" na nr top ca cr
    na="$(_cap_count "$af")"; nr="$(_cap_count "$rf")"; na="${na:-0}"; nr="${nr:-0}"
    top="$(grep -E ' IP6? ' "$af" 2>/dev/null | awk '{p=$5; sub(/\.[0-9]+$/,"",p); print p}' | sort | uniq -c | sort -rn | head -3 | awk '{printf "%s (%s)  ", $2, $1}')"
    ca="$RED"; [ "$na" -gt 0 ] && ca="$GREEN"
    cr="$RED"; [ "$nr" -gt 0 ] && cr="$GREEN"
    [ "$na" -gt 0 ] && [ "$nr" -eq 0 ] && cr="$YELLOW"
    printf "  %-22s arrived ${ca}%6s${NC}   answered ${cr}%6s${NC}   %s\n" "$label" "$na" "$nr" "${top:+from: $top}"
}

# sys_watch [seconds]  - connect from your phone/PC while this runs; it reports which ports receive your
# traffic and whether Xray / WireGuard accept it. Xray's log level is raised temporarily and restored.
sys_watch() {
    require_root
    local secs="${1:-45}" ip tmp wgport prev had_prev since acc rej ifc pk ts now
    [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -ge 5 ] && [ "$secs" -le 300 ] || { err "Seconds must be 5-300."; return 1; }
    need_cmd tcpdump || return 1
    ip="$(get_public_ip)"; tmp="$(mktemp -d)"
    wgport=""; command -v wg >/dev/null 2>&1 && wgport="$(wg_live_port 2>/dev/null)"
    had_prev=0; prev="$(setting_get xray_loglevel)"; [ -n "$prev" ] && had_prev=1
    if xray_installed; then setting_set xray_loglevel info; xray_apply >/dev/null 2>&1; fi
    since="$(date '+%Y-%m-%d %H:%M:%S')"

    echo -e "${BOLD}${YELLOW}▶ Connect NOW from your phone/PC with the VPN app (a web browser is not a VPN test).${NC}"
    echo -e "  Watching ${secs}s on $ip ..."
    local syn='tcp[tcpflags] & (tcp-syn|tcp-ack) = tcp-syn' synack='tcp[tcpflags] & (tcp-syn|tcp-ack) = (tcp-syn|tcp-ack)'
    for pt in 80 443 8443 8080; do
        timeout "$secs" tcpdump -nn -l -i any "tcp dst port $pt and dst host $ip and $syn" > "$tmp/tcp$pt" 2>/dev/null &
        timeout "$secs" tcpdump -nn -l -i any "tcp src port $pt and src host $ip and $synack" > "$tmp/tcpA$pt" 2>/dev/null &
    done
    for pt in $wgport 666 1194; do
        [ -n "$pt" ] || continue
        timeout "$secs" tcpdump -nn -l -i any "udp dst port $pt and dst host $ip" > "$tmp/udp$pt" 2>/dev/null &
        timeout "$secs" tcpdump -nn -l -i any "udp src port $pt and src host $ip" > "$tmp/udpA$pt" 2>/dev/null &
    done
    local left="$secs"
    while [ "$left" -gt 0 ]; do
        sleep $(( left > 15 ? 15 : left )); left=$(( left > 15 ? left - 15 : 0 ))
        [ "$left" -gt 0 ] && echo "  ... ${left}s left"
    done
    wait

    # restore the log level we changed
    if xray_installed; then
        if [ "$had_prev" = 1 ]; then setting_set xray_loglevel "$prev"; else setting_del xray_loglevel; fi
        acc="$(journalctl -u xray --since "$since" --no-pager 2>/dev/null | grep -c ' accepted ')"
        rej="$(journalctl -u xray --since "$since" --no-pager 2>/dev/null | grep -c 'failed to find the default')"
        journalctl -u xray --since "$since" --no-pager 2>/dev/null | grep ' accepted ' > "$tmp/accepted"
        xray_apply >/dev/null 2>&1
    fi

    echo -e "\n${BOLD}What reached this server${NC}  (arrived = seen on the network card; answered = this server replied, i.e. the firewall allowed it and something listens)"
    for pt in 80 443 8443 8080; do _watch_row "TCP $pt" "$tmp/tcp$pt" "$tmp/tcpA$pt"; done
    for pt in $wgport 666 1194; do [ -n "$pt" ] && _watch_row "UDP $pt$([ "$pt" = "$wgport" ] && echo ' (WireGuard)')" "$tmp/udp$pt" "$tmp/udpA$pt"; done

    if xray_installed; then
        echo -e "\n${BOLD}What Xray did${NC}"
        echo "  accepted connections : ${acc:-0}"
        [ -s "$tmp/accepted" ] && grep -o '\[[^]]*>>' "$tmp/accepted" | tr -d '[>' | sort | uniq -c | sort -rn | sed 's/^/      /'
        echo "  rejected (wrong path): ${rej:-0}   (a web browser, scanner, or a client with the wrong path/Host)"
    fi
    if [ -n "$wgport" ]; then
        echo -e "\n${BOLD}WireGuard peers${NC}"
        now="$(date +%s)"
        for ifc in $(wg show interfaces 2>/dev/null); do
            while read -r pk ts; do
                if [ "${ts:-0}" = 0 ]; then echo -e "  peer ${pk:0:10}…  handshake: ${RED}NEVER${NC}"
                else echo -e "  peer ${pk:0:10}…  handshake: ${GREEN}$((now - ts))s ago${NC}"; fi
            done < <(wg show "$ifc" latest-handshakes 2>/dev/null)
        done
    fi

    echo -e "\n${BOLD}How to read this${NC}"
    echo "  • arrived 0                 → your traffic never reached the server: blocked BEFORE it (ISP / mobile network / hosting panel firewall), or you did not connect during the window"
    echo "  • arrived > 0, answered 0   → it reached the server but was dropped by the firewall (ufw) or nothing listens (expected for scanners, and for Squid when it is restricted to your IPs)"
    echo "  • answered > 0              → the server accepted the connection"
    echo "  • port > 0, Xray accepted 0 → it arrives but Xray refuses it: check that the app uses exactly the link's path, host/SNI and TLS on/off"
    echo "  • UDP (WireGuard) > 0 but handshake NEVER → wrong keys / old QR code; re-scan a fresh one (vpsmanager wg add <name>)"
    rm -rf "$tmp"
}

sys_diag() {
    local ip dom dns cm ct ifc
    ip="$(get_public_ip)"; dom="$(setting_get domain)"
    echo -e "${BOLD}== Server ==${NC}"
    echo "  public IP : $ip"
    echo "  uptime    : $(uptime -p 2>/dev/null)   load: $(cut -d' ' -f1-3 /proc/loadavg)"
    ct="$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)"; cm="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"
    [ -n "$ct" ] && echo "  conntrack : $ct / $cm"
    echo "  ip_forward: $(sysctl -n net.ipv4.ip_forward 2>/dev/null)   (VPN needs 1)"

    echo -e "\n${BOLD}== Domain ==${NC}"
    if [ -n "$dom" ]; then
        dns="$(getent ahostsv4 "$dom" 2>/dev/null | awk '{print $1; exit}')"
        echo "  $dom → ${dns:-<no answer>}"
        if [ -z "$dns" ]; then warn "the domain does not resolve"
        elif [ "$dns" != "$ip" ]; then warn "it does NOT point at this server ($ip) - a CDN/proxy (e.g. Cloudflare orange cloud) or wrong A record. Plain WS on port 80 usually breaks behind 'Always Use HTTPS'."
        else ok "DNS points at this server"; fi
    else echo "  (no domain configured)"; fi

    echo -e "\n${BOLD}== Xray (WebSocket 443 / 80) ==${NC}"
    if xray_installed; then
        xray_test 2>&1 | sed 's/^/  /' | grep -vE "^  (101 =|    cert)" || true
        echo "  loopback HTTP on :80  → $(curl -s --noproxy '*' -m 4 -o /dev/null -w '%{http_code}' http://127.0.0.1:80/ 2>/dev/null) (000/400 = Xray answered or closed; refused = not listening)"
    else echo "  Xray not installed"; fi

    echo -e "\n${BOLD}== WireGuard ==${NC}"
    if command -v wg >/dev/null 2>&1 && [ -n "$(wg show interfaces 2>/dev/null)" ]; then
        for ifc in $(wg show interfaces); do
            echo "  interface $ifc  listen-port $(wg show "$ifc" listen-port)  address $(ip -4 -o addr show "$ifc" 2>/dev/null | awk '{print $4}' | xargs)"
        done
        local pk ts now; now="$(date +%s)"
        for ifc in $(wg show interfaces); do
            while read -r pk ts; do
                if [ "${ts:-0}" = 0 ]; then echo -e "  peer ${pk:0:10}…  handshake: ${RED}NEVER${NC} - this client never reached the server"
                else echo -e "  peer ${pk:0:10}…  handshake: ${GREEN}$((now - ts))s ago${NC}"; fi
            done < <(wg show "$ifc" latest-handshakes 2>/dev/null)
        done
        echo "  (NEVER = blocked UDP, wrong Endpoint/port in the client, or wrong keys; the client must use port $(wg show "$(wg show interfaces | awk '{print $1}')" listen-port))"
        echo "  NAT   : $(iptables -t nat -S POSTROUTING 2>/dev/null | grep -c MASQUERADE) MASQUERADE rule(s)"
        echo "  FWD   : $(iptables -S FORWARD 2>/dev/null | head -1)   ufw routed policy: $(grep -E '^DEFAULT_FORWARD_POLICY' /etc/default/ufw 2>/dev/null | cut -d= -f2)"
        echo "  FORWARD rules with ACCEPT: $(iptables -S FORWARD 2>/dev/null | grep -c ACCEPT)"
    else echo "  no WireGuard interface is up"; fi

    echo -e "\n${BOLD}== Firewall ==${NC}"
    if fw_active; then ufw status | grep -E "^(Status|80|443|666|1194|8080|8443|51820|22)" | sed 's/^/  /' | head -16
    else echo "  ufw inactive"; fi
    echo -e "\n${DIM}Provider firewall (the panel of your VPS host) is NOT visible from here: if packets never arrive, open the ports there too.${NC}"
    echo -e "${DIM}To see whether packets reach the server while you connect:  tcpdump -ni any 'tcp port 80 and not host 127.0.0.1' -c 8   (or: udp port 443)${NC}"
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
    local p port type kv sshports
    sshports="$(ssh_current_ports)"
    for p in $sshports; do ufw allow "$p/tcp" >/dev/null 2>&1; done
    # open everything the manager has configured
    if [ -s "$XRAY_INB" ]; then
        while read -r port type; do
            if [ "$type" = ss2022 ]; then ufw allow "$port" >/dev/null 2>&1; else ufw allow "$port/tcp" >/dev/null 2>&1; fi
        done < <(jq -r '.[] | . as $i | [$i.port, ($i.plain_port // empty)] | .[] | "\(.) \($i.type)"' "$XRAY_INB")
    fi
    for kv in hy2_port:udp wg_port:udp ovpn_port:"$(setting_get ovpn_proto)" squid_port:tcp; do
        p="$(setting_get "${kv%%:*}")"; [ -n "$p" ] && ufw allow "$p/${kv#*:}" >/dev/null 2>&1
    done
    ufw allow 80/tcp >/dev/null 2>&1
    # What is REALLY running, whatever port it uses (an existing install may differ from our settings):
    # WireGuard is a kernel socket without a process name, so ask wg itself.
    local ifc wp proto lport
    for ifc in $(wg show interfaces 2>/dev/null); do
        wp="$(wg show "$ifc" listen-port 2>/dev/null)"
        [ -n "$wp" ] && [ "$wp" != 0 ] && ufw allow "$wp/udp" >/dev/null 2>&1
    done
    # public listeners of the proxy services we manage (squid UDP ports are random, so only its TCP port)
    while read -r proto lport; do
        ufw allow "$lport/$proto" >/dev/null 2>&1
    done < <(ss -H -lntup 2>/dev/null | awk '
        $5 ~ /^(127\.|\[::1\])/ { next }
        { n = split($5, a, ":"); port = a[n] }
        /"(hysteria|openvpn)"/       { print $1, port }
        /"(xray|squid)"/ && $1 == "tcp" { print $1, port }')
    # (xray / squid UDP sockets are short-lived, randomly numbered sockets for proxied UDP flows - never opened;
    #  a real UDP inbound such as Shadowsocks-2022 is already opened from the inbound list above)
    # safety: refuse to turn the firewall on if SSH is not in the allowed set (would lock you out)
    for p in $sshports; do
        ufw show added 2>/dev/null | grep -Eq "allow ($p|$p/tcp)\b" || { err "SSH port $p is not allowed in ufw - NOT enabling the firewall."; return 1; }
    done
    ufw default deny incoming >/dev/null 2>&1; ufw default allow outgoing >/dev/null 2>&1
    ufw --force enable >/dev/null 2>&1 && ok "Firewall enabled (SSH $sshports+ configured services allowed)"
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
    pkg_install fail2ban python3-systemd || return 1
    local ports
    ports="$(ssh_current_ports | xargs | tr ' ' ',')"
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/vpsm.local <<EOF
[sshd]
enabled = true
port = $ports
maxretry = 5
findtime = 10m
bantime = 1h
backend = systemd
EOF
    systemctl enable fail2ban >/dev/null 2>&1; systemctl restart fail2ban 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        fail2ban-client ping >/dev/null 2>&1 && break
        sleep 1
    done
    if fail2ban-client status sshd >/dev/null 2>&1; then
        ok "Fail2ban active for SSH port(s) $ports (5 failures → 1 hour ban)"
        return 0
    fi
    err "Fail2ban did not start:"
    journalctl -u fail2ban -n 8 --no-pager 2>/dev/null | sed 's/^/    /'
    return 1
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
        local br
        br="$(git -C "$VPSM_HOME" rev-parse --abbrev-ref HEAD 2>/dev/null)"
        { [ -z "$br" ] || [ "$br" = HEAD ]; } && br=main
        if ! git -C "$VPSM_HOME" fetch -q origin "+refs/heads/$br:refs/remotes/origin/$br" 2>/dev/null; then
            # the branch we installed from may have been merged and deleted: follow main instead
            if [ "$br" != main ] && git -C "$VPSM_HOME" fetch -q origin +refs/heads/main:refs/remotes/origin/main 2>/dev/null; then
                warn "Branch '$br' no longer exists on GitHub - switching to main."
                br=main
            else
                err "git update failed (is github.com reachable?)"; return 1
            fi
        fi
        git -C "$VPSM_HOME" checkout -q -B "$br" "origin/$br" 2>/dev/null
        git -C "$VPSM_HOME" reset -q --hard "origin/$br" || { err "git update failed"; return 1; }
        ok "Updated to $(git -C "$VPSM_HOME" rev-parse --short HEAD) ($br)"
    else
        local tmp; tmp="$(mktemp -d)"
        curl -fsSL "https://github.com/${VPSM_REPO}/archive/refs/heads/main.tar.gz" | tar -xz -C "$tmp" --strip-components=1 \
            && cp -a "$tmp"/. "$VPSM_HOME"/ && ok "Updated" || { err "Download failed"; rm -rf "$tmp"; return 1; }
        rm -rf "$tmp"
    fi
    chmod +x "$VPSM_HOME/vpsmanager"
    if [ -f "$VPSM_HOME/bot/requirements.txt" ] && [ -d "$VPSM_HOME/venv" ]; then
        "$VPSM_HOME/venv/bin/pip" install -q -r "$VPSM_HOME/bot/requirements.txt" 2>/dev/null
    fi
    svc_active vpsm-bot && systemctl restart vpsm-bot
    log_action "self-update"
    # run the NEW code once so that fixes to generated configs take effect right away
    "$VPSM_HOME/vpsmanager" post-update
}

# Re-generate configs that this tool owns with the (new) code. Idempotent: services are only
# restarted when their generated config actually changed.
sys_post_update() {
    require_root
    sys_tune_conntrack
    xray_installed && xray_apply
    squid_installed && [ -n "$(setting_get squid_port)" ] && squid_apply
    hy2_installed && hy2_apply
    return 0
}

#---- one-click ------------------------------------------------------------------------------

# ---- full unattended setup -------------------------------------------------------------
FULL_OK=(); FULL_FAIL=()
run_step() { # run_step "label" cmd [args...]   - a failing step is reported, the rest still runs
    local label="$1"; shift
    echo -e "\n${BOLD}${CYAN}▶ $label${NC}"
    if "$@"; then FULL_OK+=("$label"); else FULL_FAIL+=("$label"); warn "Step failed: $label (continuing)"; fi
}

_f_tune()   { sys_enable_bbr; sys_tune; }
_f_swap()   { local ram; ram="$(free -m | awk '/^Mem:/{print $2}')"
              if [ "${ram:-9999}" -lt 2048 ] && ! swapon --show | grep -q .; then sys_swap; else ok "swap not needed / already present"; fi; }
_f_xray()   { xray_installed || xray_install; }
_f_ws()     { xray_inbound_exists multi-ws-443 || xray_add_inbound multi-ws 443 "$FULL_DOMAIN" 80; }
_f_reality(){ xray_inbound_exists reality-8443 || xray_add_inbound reality 8443 "" "www.microsoft.com"; }
_f_hy2()    { hy2_installed && { ok "Hysteria 2 already installed"; return 0; }; hy2_install 443 -; }
_f_wg()     { wg_installed && { ok "WireGuard already installed"; return 0; }; wg_install; }
_f_ovpn()   { ovpn_installed && { ok "OpenVPN already installed"; return 0; }; ovpn_install; }
_f_squid()  { squid_installed && { ok "Squid already installed"; squid_apply; return; }; squid_install 8080; }
_f_udpgw()  { [ -x "$UDPGW_BIN" ] && svc_active "$UDPGW_SVC" && { ok "UDPGW already running"; return 0; }; udpgw_install 7300; }
_f_user()   { user_exists "$FULL_USER" && { ok "user '$FULL_USER' already exists"; return 0; }; user_add "$FULL_USER" 0; }
_f_apply()  { apply_all; }

# full_setup [first-user] [domain]  - installs and hardens everything, unattended and idempotent
full_setup() {
    require_root
    export VPSM_NONINTERACTIVE=1
    FULL_USER="${1:-admin}"; FULL_DOMAIN="${2:-}"; FULL_OK=(); FULL_FAIL=()
    valid_name "$FULL_USER" || { err "Invalid user name."; return 1; }
    info "Full setup: tuning, security, Xray (WS 443+80, Reality), Hysteria2, WireGuard, OpenVPN, Squid, UDPGW"

    run_step "System tuning (BBR, limits, conntrack)" _f_tune
    run_step "Swap (small servers)"                   _f_swap
    run_step "Fail2ban (SSH brute-force protection)"  sys_fail2ban
    run_step "First user '$FULL_USER'"                _f_user
    if [ -n "$FULL_DOMAIN" ]; then
        if ssl_have_le "$FULL_DOMAIN"; then ok "certificate for $FULL_DOMAIN already present"
        else
            run_step "SSL certificate for $FULL_DOMAIN" ssl_issue "$FULL_DOMAIN"
            if ! ssl_have_le "$FULL_DOMAIN"; then
                warn "No certificate yet - continuing with a self-signed one on 443."
                warn "When DNS points here: vpsmanager ssl issue $FULL_DOMAIN && vpsmanager xray del multi-ws-443 && vpsmanager xray add multi-ws 443 $FULL_DOMAIN 80"
                FULL_DOMAIN=""
            fi
        fi
    fi
    run_step "Xray-core"                              _f_xray
    run_step "Xray: VLESS/VMess/Trojan/SS over WebSocket on 443 (SSL) + 80"  _f_ws
    run_step "Xray: VLESS + Reality on 8443"          _f_reality
    run_step "Hysteria 2"                             _f_hy2
    run_step "WireGuard"                              _f_wg
    run_step "OpenVPN"                               _f_ovpn
    run_step "Squid HTTP proxy (open)"                _f_squid
    run_step "BadVPN UDPGW"                           _f_udpgw
    run_step "Apply users to all protocols"           _f_apply
    run_step "Firewall (ufw)"                         fw_enable

    echo -e "\n$LINE"
    echo -e "${BOLD}Summary${NC}"
    local x
    for x in "${FULL_OK[@]}";   do echo -e "  ${GREEN}✔${NC} $x"; done
    for x in "${FULL_FAIL[@]}"; do echo -e "  ${RED}✖${NC} $x"; done
    echo -e "$LINE"
    if [ "${#FULL_FAIL[@]}" -gt 0 ]; then
        warn "${#FULL_FAIL[@]} step(s) failed. Fix the cause shown above and run again - installed parts are skipped:  vpsmanager full-setup $FULL_USER ${FULL_DOMAIN}"
    else
        ok "Everything installed."
    fi
    echo ""; user_show "$FULL_USER"
    echo -e "$LINE"; sys_ports
    echo ""
    echo -e "  WireGuard client : ${BOLD}vpsmanager wg add <name>${NC}     OpenVPN client : ${BOLD}vpsmanager ovpn add <name>${NC}"
    echo -e "  Check WebSocket  : ${BOLD}vpsmanager xray test${NC}          Restrict Squid : ${BOLD}vpsmanager squid ip <your-IP>${NC}"
    [ "${#FULL_FAIL[@]}" -eq 0 ]
}

quick_setup() { full_setup "$@"; }

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
