#!/usr/bin/env bash
# Removes VPS Manager Pro itself. Installed services (Xray, WireGuard, ...) are
# NOT touched - remove them from the menu first if you want them gone.
[ "$EUID" -eq 0 ] || { echo "Run as root." >&2; exit 1; }
read -rp "Remove VPS Manager Pro (configs in /etc/vps-manager are kept unless you answer 'purge')? [y/N/purge] " a
case "$a" in y|Y|purge) ;; *) exit 0 ;; esac
systemctl disable --now vpsm-expire.timer vpsm-bot >/dev/null 2>&1
rm -f /etc/systemd/system/vpsm-expire.* /etc/systemd/system/vpsm-bot.service
systemctl daemon-reload
rm -f /usr/local/bin/vpsmanager /usr/local/bin/menu
rm -rf /opt/vps-manager-pro
[ "$a" = purge ] && rm -rf /etc/vps-manager /var/log/vps-manager
echo "Removed."
