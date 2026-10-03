#!/usr/bin/env bash
#==============================================================================
# SSH server management, SSH tunnel accounts (with expiry) and BadVPN UDPGW
#==============================================================================

SSHD_CONF="/etc/ssh/sshd_config"
UDPGW_BIN="/usr/local/bin/badvpn-udpgw"
UDPGW_SVC="badvpn-udpgw"

ssh_service() { systemctl list-unit-files ssh.service >/dev/null 2>&1 && echo ssh || echo sshd; }

ssh_current_ports() { awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ {print $2}' "$SSHD_CONF" | sort -un | tr '\n' ' '; }

ssh_reload() {
    sshd -t 2>/dev/null || { err "sshd_config is invalid - not restarting."; sshd -t; return 1; }
    # Ubuntu 22.10+ uses socket activation which ignores 'Port' in sshd_config
    if svc_active ssh.socket; then
        systemctl disable --now ssh.socket >/dev/null 2>&1
        systemctl enable --now ssh >/dev/null 2>&1
    fi
    systemctl restart "$(ssh_service)" && ok "SSH restarted" || err "SSH restart failed"
}

ssh_backup_conf() { cp -n "$SSHD_CONF" "$SSHD_CONF.vpsm-orig" 2>/dev/null; cp "$SSHD_CONF" "$SSHD_CONF.bak.$(date +%s)"; }

ssh_set_option() { # ssh_set_option Key Value
    local key="$1" val="$2"
    if grep -qE "^[#[:space:]]*${key}[[:space:]]" "$SSHD_CONF"; then
        sed -i -E "0,/^[#[:space:]]*${key}[[:space:]].*/s//${key} ${val}/" "$SSHD_CONF"
    else
        echo "$key $val" >> "$SSHD_CONF"
    fi
}

ssh_add_port() {
    local port="$1" replace="${2:-no}"
    valid_port "$port" || { err "Invalid port."; return 1; }
    port_in_use "$port" tcp && ! ssh_current_ports | grep -qw "$port" && { err "Port $port is in use."; return 1; }
    ssh_backup_conf
    if [ "$replace" = yes ]; then
        sed -i -E '/^[[:space:]]*Port[[:space:]]+[0-9]+/d' "$SSHD_CONF"
    fi
    grep -qE "^Port[[:space:]]+$port\$" "$SSHD_CONF" || echo "Port $port" >> "$SSHD_CONF"
    # keep default 22 listening unless it was explicitly replaced
    fw_allow "$port" tcp
    ssh_reload && ok "SSH now listens on: $(ssh_current_ports)"
    log_action "ssh port: $port (replace=$replace)"
}

ssh_toggle_root() {
    ssh_backup_conf
    local cur; cur="$(sshd -T 2>/dev/null | awk '/^permitrootlogin/ {print $2}')"
    if [ "$cur" = no ]; then ssh_set_option PermitRootLogin yes; ok "Root login enabled"
    else ssh_set_option PermitRootLogin prohibit-password; ok "Root login: key-only"; fi
    ssh_reload
}

ssh_toggle_password_auth() {
    ssh_backup_conf
    local cur; cur="$(sshd -T 2>/dev/null | awk '/^passwordauthentication/ {print $2}')"
    if [ "$cur" = yes ]; then
        [ -s /root/.ssh/authorized_keys ] || warn "No key found in /root/.ssh/authorized_keys - you may lock yourself out!"
        confirm "Disable password login?" n || return
        ssh_set_option PasswordAuthentication no; ok "Password login disabled"
    else
        ssh_set_option PasswordAuthentication yes; ok "Password login enabled"
    fi
    ssh_reload
}

ssh_add_key() { # ssh_add_key "<public key>"
    [[ "$1" =~ ^(ssh-(rsa|ed25519)|ecdsa-sha2-) ]] || { err "That does not look like a public key."; return 1; }
    mkdir -p /root/.ssh; chmod 700 /root/.ssh
    echo "$1" >> /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys
    ok "Key added to /root/.ssh/authorized_keys"
}

#---- tunnel accounts ----------------------------------------------------------------

# ssh_user_add NAME DAYS [PASSWORD] [MAXLOGINS]
ssh_user_add() {
    local name="$1" days="${2:-30}" pass="${3:-$(rand_str 12)}" max="${4:-0}" exp=""
    valid_name "$name" || { err "Invalid name."; return 1; }
    id "$name" >/dev/null 2>&1 && { err "System user '$name' already exists."; return 1; }
    [[ "$days" =~ ^[0-9]+$ ]] || { err "Days must be a number."; return 1; }
    [ "$days" -gt 0 ] && exp="$(date -d "+$days days" +%F)"
    useradd -M -s /usr/sbin/nologin ${exp:+-e "$exp"} -c "vpsm-ssh" "$name" || return 1
    echo "$name:$pass" | chpasswd
    if [ "$max" -gt 0 ]; then
        mkdir -p /etc/security/limits.d
        echo "$name hard maxlogins $max" > "/etc/security/limits.d/vpsm-$name.conf"
    fi
    log_action "ssh user added: $name ($days days)"
    ok "SSH account created"
    echo "  Host: $(get_public_ip)   Port: $(ssh_current_ports)"
    echo "  User: $name   Password: $pass   Expires: ${exp:-never}   Max logins: $([ "$max" -gt 0 ] && echo "$max" || echo unlimited)"
}

ssh_user_del() {
    getent passwd "$1" | grep -q vpsm-ssh || { err "'$1' is not a managed SSH account."; return 1; }
    pkill -u "$1" 2>/dev/null
    userdel "$1" 2>/dev/null; rm -f "/etc/security/limits.d/vpsm-$1.conf"
    log_action "ssh user deleted: $1"; ok "SSH account '$1' deleted"
}

ssh_user_renew() { # ssh_user_renew NAME DAYS
    getent passwd "$1" | grep -q vpsm-ssh || { err "'$1' is not a managed SSH account."; return 1; }
    chage -E "$(date -d "+$2 days" +%F)" "$1" && ok "'$1' now expires $(date -d "+$2 days" +%F)"
}

ssh_user_list() {
    local found=0
    printf "${BOLD}%-18s %-12s %s${NC}\n" "USER" "EXPIRES" "ONLINE"
    while IFS=: read -r u _ _ _ c _; do
        [ "$c" = vpsm-ssh ] || continue
        found=1
        printf "%-18s %-12s %s\n" "$u" "$(chage -l "$u" | awk -F': ' '/Account expires/ {print $2}')" "$(who | awk -v u="$u" '$1==u' | wc -l)"
    done < /etc/passwd
    [ $found -eq 0 ] && echo "No SSH accounts."
    return 0
}

ssh_sessions() { who; echo ""; ss -tnp 2>/dev/null | grep -E "sshd" | head -20; }

#---- BadVPN UDPGW -----------------------------------------------------------------

udpgw_install() {
    require_root
    local port="${1:-7300}"
    info "Building BadVPN UDPGW (needed for UDP/gaming/calls over SSH apps)..."
    pkg_install cmake build-essential git || return 1
    local tmp; tmp="$(mktemp -d)"
    git clone --depth 1 https://github.com/ambrop72/badvpn.git "$tmp/badvpn" >/dev/null 2>&1 || { err "git clone failed"; rm -rf "$tmp"; return 1; }
    ( cd "$tmp/badvpn" && mkdir build && cd build \
      && cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 >/dev/null 2>&1 \
      && make -j"$(nproc)" >/dev/null 2>&1 \
      && install -m 755 udpgw/badvpn-udpgw "$UDPGW_BIN" ) || { err "Build failed."; rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    cat > "/etc/systemd/system/$UDPGW_SVC.service" <<EOF
[Unit]
Description=BadVPN UDP gateway
After=network.target

[Service]
ExecStart=$UDPGW_BIN --listen-addr 127.0.0.1:$port --max-clients 1000 --max-connections-for-client 20
Restart=always
User=nobody
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable --now "$UDPGW_SVC" >/dev/null 2>&1
    svc_active "$UDPGW_SVC" && ok "UDPGW listening on 127.0.0.1:$port (use it from your SSH client app)" || err "UDPGW failed to start"
    setting_set udpgw_port "$port"
}

#---- menu -------------------------------------------------------------------------

ssh_menu() {
    while true; do
        menu_header "🔐 SSH   (ports: $(ssh_current_ports))   UDPGW: $(svc_state "$UDPGW_SVC")"
        echo "  1) Change SSH port            7) Create tunnel account"
        echo "  2) Add extra SSH port         8) Delete tunnel account"
        echo "  3) Toggle root login          9) Renew tunnel account"
        echo "  4) Toggle password login     10) List tunnel accounts"
        echo "  5) Add public key            11) Install BadVPN UDPGW"
        echo "  6) Active sessions           12) Restart SSH"
        echo "  0) Back"
        echo -e "$LINE"
        case "$(ask "Choose" "")" in
            1) ssh_add_port "$(ask "New SSH port" 2222)" yes; pause ;;
            2) ssh_add_port "$(ask "Extra SSH port" 2222)" no; pause ;;
            3) ssh_toggle_root; pause ;;
            4) ssh_toggle_password_auth; pause ;;
            5) ssh_add_key "$(ask "Paste public key" "")"; pause ;;
            6) ssh_sessions; pause ;;
            7) ssh_user_add "$(ask "Username" "")" "$(ask "Days valid (0 = never)" 30)" "$(ask "Password (empty = random)" "")" "$(ask "Max simultaneous logins (0 = unlimited)" 0)"; pause ;;
            8) ssh_user_list; ssh_user_del "$(ask "Username" "")"; pause ;;
            9) ssh_user_list; ssh_user_renew "$(ask "Username" "")" "$(ask "Days from today" 30)"; pause ;;
            10) ssh_user_list; pause ;;
            11) udpgw_install "$(ask "UDPGW port" 7300)"; pause ;;
            12) ssh_reload; pause ;;
            0|"") return ;;
        esac
    done
}
