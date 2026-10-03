#!/usr/bin/env bash
# shellcheck disable=SC2034
#==============================================================================
# VPS Manager Pro - shared helpers
#==============================================================================

VPSM_VERSION="6.0.0"
VPSM_HOME="${VPSM_HOME:-/opt/vps-manager-pro}"
VPSM_ETC="${VPSM_ETC:-/etc/vps-manager}"
VPSM_LOG_DIR="${VPSM_LOG_DIR:-/var/log/vps-manager}"
VPSM_BACKUP_DIR="${VPSM_BACKUP_DIR:-/var/backups/vps-manager}"
VPSM_REPO="${VPSM_REPO:-AndamAziz/vps-pro-maneger}"

USERS_DB="$VPSM_ETC/users.json"
SETTINGS_DB="$VPSM_ETC/settings.json"
CERT_DIR="$VPSM_ETC/certs"

# ---- colours ---------------------------------------------------------------
if [ -t 1 ]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi
LINE="${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ---- messages --------------------------------------------------------------
info()  { echo -e "${CYAN}➜${NC} $*"; }
ok()    { echo -e "${GREEN}✔${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}✖${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

log_action() {
    mkdir -p "$VPSM_LOG_DIR" 2>/dev/null || return 0
    echo "[$(date '+%F %T')] $*" >> "$VPSM_LOG_DIR/vps-manager.log" 2>/dev/null || true
}

pause() {
    [ "${VPSM_NONINTERACTIVE:-0}" = 1 ] && return 0
    echo ""
    read -rp "Press Enter to continue..." _ </dev/tty 2>/dev/null || true
}

# ask "Prompt" "default" -> echoes the answer
ask() {
    local prompt="$1" default="${2:-}" reply
    if [ "${VPSM_NONINTERACTIVE:-0}" = 1 ]; then echo "$default"; return; fi
    if [ -n "$default" ]; then
        read -rp "$prompt [$default]: " reply </dev/tty
    else
        read -rp "$prompt: " reply </dev/tty
    fi
    echo "${reply:-$default}"
}

# confirm "Question" [default y|n]
confirm() {
    local def="${2:-n}" reply
    [ "${VPSM_NONINTERACTIVE:-0}" = 1 ] && { [ "$def" = y ]; return; }
    read -rp "$1 [$([ "$def" = y ] && echo Y/n || echo y/N)]: " reply </dev/tty
    reply="${reply:-$def}"
    [[ "$reply" =~ ^[Yy] ]]
}

# ---- environment -----------------------------------------------------------
require_root() {
    [ "$EUID" -eq 0 ] || die "This command must be run as root (use sudo)."
}

detect_os() {
    OS_ID="unknown"; OS_VER=""; OS_NAME="unknown"
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"; OS_VER="${VERSION_ID:-}"; OS_NAME="${PRETTY_NAME:-$OS_ID}"
    fi
    OS_ARCH="$(uname -m)"
}

require_supported_os() {
    detect_os
    command -v apt-get >/dev/null 2>&1 || die "Unsupported OS ($OS_NAME). Debian / Ubuntu based systems are required."
    command -v systemctl >/dev/null 2>&1 || die "systemd is required."
}

pkg_install() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null 2>&1 || {
        apt-get update -qq >/dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null 2>&1
    } || { err "Failed to install: $*"; return 1; }
}

need_cmd() { # need_cmd cmd [package]
    command -v "$1" >/dev/null 2>&1 && return 0
    info "Installing ${2:-$1}..."
    pkg_install "${2:-$1}"
}

# ---- network ---------------------------------------------------------------
get_public_ip() {
    local ip svc
    ip="$(setting_get public_ip 2>/dev/null)"
    [ -n "$ip" ] && [ "$ip" != null ] && { echo "$ip"; return; }
    local cache="$VPSM_ETC/.ip_cache"
    if [ -s "$cache" ] && [ -n "$(find "$cache" -mmin -60 2>/dev/null)" ]; then cat "$cache"; return; fi
    for svc in https://api.ipify.org https://ifconfig.me https://icanhazip.com https://ipinfo.io/ip; do
        ip="$(curl -4 -fsS -m 6 "$svc" 2>/dev/null | tr -d '[:space:]')"
        if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then echo "$ip" | tee "$cache" 2>/dev/null; return; fi
    done
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"
    echo "${ip:-127.0.0.1}"
}

default_iface() { ip -4 route show default 2>/dev/null | awk '{print $5; exit}'; }

valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

# port_in_use PORT [tcp|udp]
port_in_use() {
    local port="$1" proto="${2:-tcp}" flag="-ltn"
    [ "$proto" = udp ] && flag="-lun"
    ss "$flag" 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}\$"
}

# port_used_by_other PORT -> true when a non-xray process listens on PORT (tcp or udp)
port_used_by_other() {
    ss -lntup 2>/dev/null | awk -v p=":$1\$" '$5 ~ p' | grep -v '"xray"' | grep -q .
}

# ask_port "label" default [proto]
ask_port() {
    local label="$1" def="$2" proto="${3:-tcp}" p
    while true; do
        p="$(ask "$label port" "$def")"
        valid_port "$p" || { err "Invalid port."; [ "${VPSM_NONINTERACTIVE:-0}" = 1 ] && return 1; continue; }
        if port_in_use "$p" "$proto"; then
            warn "Port $p/$proto is already in use."
            [ "${VPSM_NONINTERACTIVE:-0}" = 1 ] && return 1
            confirm "Use it anyway?" n || continue
        fi
        echo "$p"; return 0
    done
}

# ---- firewall --------------------------------------------------------------
fw_active() { command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "^Status: active"; }

fw_allow() { # fw_allow PORT tcp|udp|both
    local port="$1" proto="${2:-tcp}"
    fw_active || return 0
    if [ "$proto" = both ]; then ufw allow "$port" >/dev/null 2>&1; else ufw allow "$port/$proto" >/dev/null 2>&1; fi
}

fw_deny() {
    local port="$1" proto="${2:-tcp}"
    fw_active || return 0
    if [ "$proto" = both ]; then ufw delete allow "$port" >/dev/null 2>&1; else ufw delete allow "$port/$proto" >/dev/null 2>&1; fi
}

# ---- random / encoding -----------------------------------------------------
rand_str() { # rand_str LEN
    local len="${1:-16}"
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len"
}
rand_hex() { openssl rand -hex "${1:-8}"; }
new_uuid() { cat /proc/sys/kernel/random/uuid; }
urlenc() { jq -rn --arg s "$1" '$s|@uri'; }
b64() { printf '%s' "$1" | base64 -w0; }

# ---- json state ------------------------------------------------------------
db_init() {
    mkdir -p "$VPSM_ETC" "$CERT_DIR" "$VPSM_LOG_DIR" "$VPSM_BACKUP_DIR"
    chmod 700 "$VPSM_ETC"
    [ -s "$USERS_DB" ] || echo '[]' > "$USERS_DB"
    [ -s "$SETTINGS_DB" ] || echo '{}' > "$SETTINGS_DB"
    chmod 600 "$USERS_DB" "$SETTINGS_DB"
}

# json_write FILE  (reads new content on stdin, validates, replaces atomically)
json_write() {
    local file="$1" tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    if jq . >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        chmod --reference="$file" "$tmp" 2>/dev/null || chmod 600 "$tmp"
        mv "$tmp" "$file"
    else
        rm -f "$tmp"; err "Refusing to write invalid JSON to $file"; return 1
    fi
}

setting_get() { [ -s "$SETTINGS_DB" ] && jq -r --arg k "$1" '.[$k] // empty' "$SETTINGS_DB"; }
setting_set() { jq --arg k "$1" --arg v "$2" '.[$k]=$v' "$SETTINGS_DB" | json_write "$SETTINGS_DB"; }
setting_del() { jq --arg k "$1" 'del(.[$k])' "$SETTINGS_DB" | json_write "$SETTINGS_DB"; }

# ---- services --------------------------------------------------------------
svc_active()  { systemctl is-active --quiet "$1" 2>/dev/null; }
svc_enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }
svc_state() {
    if svc_active "$1"; then echo -e "${GREEN}running${NC}"
    elif systemctl list-unit-files "$1.service" 2>/dev/null | grep -q "$1"; then echo -e "${RED}stopped${NC}"
    else echo -e "${DIM}not installed${NC}"; fi
}
svc_restart() { systemctl restart "$1" 2>/dev/null && ok "$1 restarted" || err "Failed to restart $1 (see: journalctl -u $1 -n 30)"; }

# ---- UI --------------------------------------------------------------------
banner() {
    [ "${VPSM_NONINTERACTIVE:-0}" = 1 ] && return 0
    clear 2>/dev/null || true
    echo -e "${CYAN}"
    cat <<'EOF'
 _  __                 _  ____ _                 _
| |/ /_   _ _ __ __| |/ ___| | ___  _   _  __| |
| ' /| | | | '__/ _` | |   | |/ _ \| | | |/ _` |
| . \| |_| | | | (_| | |___| | (_) | |_| | (_| |
|_|\_\\__,_|_|  \__,_|\____|_|\___/ \__,_|\__,_|
EOF
    echo -e "${NC}${GREEN}  VPS Manager Pro v${VPSM_VERSION}${NC}  ${DIM}github.com/${VPSM_REPO}${NC}"
    echo -e "$LINE"
}

# menu_header "Title"
menu_header() { banner; echo -e "${BOLD}${CYAN}$1${NC}"; echo -e "$LINE"; }

human_bytes() {
    awk -v b="${1:-0}" 'BEGIN{
        split("B KB MB GB TB",u," "); i=1;
        while (b>=1024 && i<5) { b/=1024; i++ }
        printf (i==1 ? "%d %s" : "%.2f %s"), b, u[i] }'
}

show_qr() { # show_qr TEXT
    command -v qrencode >/dev/null 2>&1 || pkg_install qrencode || return 0
    qrencode -t ANSIUTF8 -m 1 "$1" 2>/dev/null
}
