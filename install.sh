#!/usr/bin/env bash
#==============================================================================
# KurdCloud VPS Manager Pro - installer
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/install.sh)
#
# Options:
#   --branch NAME     install a different branch (default: main)
#   --quick [USER]    run the one-click setup right after installing
#   --no-menu         do not open the menu when finished
#==============================================================================
set -e

REPO="${VPSM_REPO:-AndamAziz/vps-pro-maneger}"
BRANCH="main"
HOME_DIR="/opt/vps-manager-pro"
QUICK=0; QUICK_USER="admin"; OPEN_MENU=1

while [ $# -gt 0 ]; do
    case "$1" in
        --branch)  BRANCH="$2"; shift 2 ;;
        --quick)   QUICK=1; OPEN_MENU=0; if [ -n "${2:-}" ] && [[ "$2" != --* ]]; then QUICK_USER="$2"; shift; fi; shift ;;
        --no-menu) OPEN_MENU=0; shift ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

R=$'\033[0;31m'; G=$'\033[0;32m'; Y=$'\033[1;33m'; C=$'\033[0;36m'; N=$'\033[0m'
step() { echo -e "${C}➜${N} $*"; }
fail() { echo -e "${R}✖ $*${N}" >&2; exit 1; }

[ "$EUID" -eq 0 ] || fail "Please run as root:  sudo bash install.sh"
command -v apt-get >/dev/null 2>&1 || fail "Only Debian / Ubuntu based systems are supported."
command -v systemctl >/dev/null 2>&1 || fail "systemd is required."

if [ -r /etc/os-release ]; then . /etc/os-release; step "Detected: ${PRETTY_NAME:-unknown} ($(uname -m))"; fi

step "Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y -qq curl ca-certificates jq openssl qrencode git tar iproute2 iptables >/dev/null 2>&1 \
    || fail "Could not install base packages (check your network / apt sources)."

step "Fetching VPS Manager Pro ($REPO@$BRANCH)..."
if [ -d "$HOME_DIR/.git" ]; then
    git -C "$HOME_DIR" fetch -q origin "$BRANCH" && git -C "$HOME_DIR" checkout -q "$BRANCH" 2>/dev/null || true
    git -C "$HOME_DIR" reset -q --hard "origin/$BRANCH" || fail "Update failed."
elif git clone -q --depth 1 -b "$BRANCH" "https://github.com/$REPO.git" "$HOME_DIR.new" 2>/dev/null; then
    rm -rf "$HOME_DIR"; mv "$HOME_DIR.new" "$HOME_DIR"
else
    rm -rf "$HOME_DIR.new"; mkdir -p "$HOME_DIR"
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$HOME_DIR" --strip-components=1 \
        || fail "Download failed. Check that github.com is reachable."
fi

chmod +x "$HOME_DIR/vpsmanager"
ln -sf "$HOME_DIR/vpsmanager" /usr/local/bin/vpsmanager
ln -sf "$HOME_DIR/vpsmanager" /usr/local/bin/menu 2>/dev/null || true

step "Installing daily expiry timer..."
cp "$HOME_DIR/systemd/vpsm-expire.service" "$HOME_DIR/systemd/vpsm-expire.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now vpsm-expire.timer >/dev/null 2>&1

mkdir -p /etc/vps-manager /var/log/vps-manager /var/backups/vps-manager
chmod 700 /etc/vps-manager

echo ""
echo -e "${G}✔ VPS Manager Pro installed.${N}"
echo -e "  Open the menu any time with: ${Y}vpsmanager${N}   (or just ${Y}menu${N})"
echo ""

if [ "$QUICK" -eq 1 ]; then
    exec "$HOME_DIR/vpsmanager" quick-setup "$QUICK_USER"
elif [ "$OPEN_MENU" -eq 1 ] && [ -r /dev/tty ]; then
    exec "$HOME_DIR/vpsmanager" </dev/tty
fi
