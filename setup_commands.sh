#!/bin/bash
################################################################################
# VPS Manager Pro - Commands Setup Script
# Creates global commands for easy access
################################################################################

echo "Setting up VPS Manager Pro commands..."

# Create commands directory
SCRIPTS_DIR="$HOME/github-upload/scripts"

# Create global commands
echo "Creating global commands..."

sudo tee /usr/local/bin/vpsmanager > /dev/null << 'EOF'
#!/bin/bash
sudo bash ~/github-upload/scripts/vps_manager.sh "$@"
EOF

sudo tee /usr/local/bin/vpsssh > /dev/null << 'EOF'
#!/bin/bash
sudo bash ~/github-upload/scripts/ssh_manager.sh "$@"
EOF

sudo tee /usr/local/bin/vpsproxy > /dev/null << 'EOF'
#!/bin/bash
sudo bash ~/github-upload/scripts/proxy_manager.sh "$@"
EOF

sudo tee /usr/local/bin/vpsv2ray > /dev/null << 'EOF'
#!/bin/bash
sudo bash ~/github-upload/scripts/v2ray_manager.sh "$@"
EOF

sudo tee /usr/local/bin/vpsssl > /dev/null << 'EOF'
#!/bin/bash
sudo bash ~/github-upload/scripts/ssl_manager.sh "$@"
EOF

sudo tee /usr/local/bin/vpsdb > /dev/null << 'EOF'
#!/bin/bash
sudo bash ~/github-upload/scripts/database_manager.sh "$@"
EOF

sudo tee /usr/local/bin/vpsstats > /dev/null << 'EOF'
#!/bin/bash
sudo bash ~/github-upload/scripts/stats_dashboard.sh "$@"
EOF

sudo tee /usr/local/bin/vpshelp > /dev/null << 'EOF'
#!/bin/bash
cat << 'HELP'
╔══════════════════════════════════════════════════════════════╗
║           VPS MANAGER PRO - AVAILABLE COMMANDS               ║
╚══════════════════════════════════════════════════════════════╝

Management Commands:
  vpsmanager    - 🎛️  Master Control Panel
  vpsssh        - 👤 SSH User Management
  vpsproxy      - 🌐 Proxy User Management
  vpsv2ray      - 🔒 V2Ray VPN Management
  vpsssl        - 🔑 SSL Certificate Management
  vpsdb         - 💾 Database Management
  vpsstats      - 📊 Statistics Dashboard

Bot Commands:
  vpsbot start/stop/restart/status/logs

Help:
  vpshelp       - Show this help
HELP
EOF

# Make executable
sudo chmod +x /usr/local/bin/vpsmanager
sudo chmod +x /usr/local/bin/vpsssh
sudo chmod +x /usr/local/bin/vpsproxy
sudo chmod +x /usr/local/bin/vpsv2ray
sudo chmod +x /usr/local/bin/vpsssl
sudo chmod +x /usr/local/bin/vpsdb
sudo chmod +x /usr/local/bin/vpsstats
sudo chmod +x /usr/local/bin/vpshelp

echo ""
echo "✅ Commands installed successfully!"
echo ""
echo "Available commands:"
echo "  vpsmanager, vpsssh, vpsproxy, vpsv2ray"
echo "  vpsssl, vpsdb, vpsstats, vpshelp"
echo ""
echo "Type 'vpshelp' for more information"
echo ""
