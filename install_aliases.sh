#!/bin/bash
echo "Installing VPS Manager Pro aliases..."

cat >> ~/.bashrc << 'EOF'

# VPS Manager Pro - Quick Access
alias vpsmanager='sudo bash /opt/vps-manager/scripts/vps_manager.sh'
alias vpsssh='sudo bash /opt/vps-manager/scripts/ssh_manager.sh'
alias vpsproxy='sudo bash /opt/vps-manager/scripts/proxy_manager.sh'
alias vpsv2ray='sudo bash /opt/vps-manager/scripts/v2ray_manager.sh'
alias vpsssl='sudo bash /opt/vps-manager/scripts/ssl_manager.sh'
alias vpsdb='sudo bash /opt/vps-manager/scripts/database_manager.sh'
alias vpsstats='sudo bash /opt/vps-manager/scripts/stats_dashboard.sh'
EOF

source ~/.bashrc

echo "✅ Aliases installed!"
echo ""
echo "Available commands:"
echo "  vpsmanager  - Master control panel"
echo "  vpsssh      - SSH management"
echo "  vpsproxy    - Proxy management"
echo "  vpsv2ray    - V2Ray management"
echo "  vpsssl      - SSL management"
echo "  vpsdb       - Database management"
echo "  vpsstats    - Statistics dashboard"
echo "  vpsbot      - Bot control (start/stop/restart/status/logs)"
