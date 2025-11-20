# 🚀 VPS Manager Pro v5.0

<div align="center">

![Version](https://img.shields.io/badge/version-5.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Ubuntu%2024.04-orange.svg)
![Status](https://img.shields.io/badge/status-production-brightgreen.svg)

**Professional VPS Management System with 5 Integrated Services**

[Features](#-features) • [Installation](#-installation) • [Services](#-services) • [Usage](#-usage) • [Screenshots](#-screenshots)

</div>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Services](#-services)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Usage Guide](#-usage-guide)
- [Commands Reference](#-commands-reference)
- [Configuration](#-configuration)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🎯 Overview

**VPS Manager Pro** is a comprehensive, all-in-one management system for Ubuntu VPS servers. It provides a unified interface to manage multiple VPN and proxy services, with automated user management, SSL certificates, database operations, and real-time monitoring.

### Why VPS Manager Pro?

- ✅ **5 Services in One**: SSH, Squid Proxy, V2Ray, OpenVPN, SOCKS5
- ✅ **Professional UI**: Beautiful terminal interface with color coding
- ✅ **Auto Management**: User expiry, traffic limits, database backups
- ✅ **Production Ready**: Battle-tested on live servers
- ✅ **Easy to Use**: One command to install, simple menus to operate
- ✅ **Kurdish Support**: Full Kurdish language interface available

---

## ✨ Features

### 🔐 Security
- Multi-protocol VPN support (V2Ray, OpenVPN)
- Encrypted proxy connections (SOCKS5, HTTP/HTTPS)
- SSL/TLS certificate management with Let's Encrypt
- User authentication for all services
- Automatic firewall configuration

### 👥 User Management
- Create/delete users across all services
- Set expiration dates (auto-expire)
- Traffic limit tracking
- User status monitoring
- Bulk operations support

### 📊 Monitoring & Analytics
- Real-time connection status
- Traffic usage statistics
- System resource monitoring (CPU, RAM, Disk)
- Service health checks
- Connection logs

### 🗄️ Database Management
- MySQL integration for all services
- Automated backups
- Easy restore functionality
- User data persistence
- Query interface

### 🎨 User Interface
- Beautiful ASCII art banners
- Color-coded menus
- Clear status indicators
- Progress feedback
- Error handling with helpful messages

---

## 🛠️ Services

### 1. 👤 SSH User Management
- **Port**: 22
- **Features**: 
  - Shell access control
  - Password management
  - Expiry tracking
  - Connection monitoring

### 2. 🌐 Squid HTTP Proxy
- **Ports**: 3128, 8080
- **Features**:
  - HTTP/HTTPS proxying
  - Username/password authentication
  - Traffic filtering
  - Caching support
  - Dual port configuration

### 3. 🔒 V2Ray VPN
- **Ports**: 443 (TLS), 87 (HTTP)
- **Protocols**: VLESS, VMess, Trojan
- **Features**:
  - TLS encryption
  - WebSocket transport
  - Multiple protocols
  - QR code generation
  - Config file download links

### 4. 🔐 OpenVPN
- **Ports**: 1194 (UDP), 1443 (TCP)
- **Features**:
  - UDP for speed
  - TCP for stability
  - Certificate-based authentication
  - Mobile-compatible configs
  - Direct connection (no proxy required)
  - .ovpn file generation

### 5. 🧦 SOCKS5 Proxy (NEW!)
- **Port**: 1080
- **Features**:
  - Dante SOCKS5 server
  - TCP and UDP support
  - Username/password authentication
  - Faster than HTTP proxy
  - Perfect for gaming, torrents
  - Works with any protocol

---

## 📦 Requirements

### System Requirements
- **OS**: Ubuntu 24.04 LTS (recommended) or Ubuntu 22.04
- **RAM**: Minimum 1GB (2GB+ recommended)
- **Disk**: 10GB+ free space
- **CPU**: 1 core minimum (2+ recommended)

### Network Requirements
- Public IPv4 address
- Domain name (for SSL certificates)
- Open ports: 22, 80, 443, 1080, 1194, 1443, 3128, 8080

### Software Requirements
- Root or sudo access
- Git installed
- MySQL/MariaDB (auto-installed)
- Nginx (auto-installed)

---

## 🚀 Installation

### One-Line Installation
```bash
bash <(curl -s https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/install.sh)
```

### Manual Installation
```bash
# 1. Clone repository
git clone https://github.com/AndamAziz/vps-pro-maneger.git
cd vps-pro-maneger

# 2. Run installer
chmod +x install.sh
sudo ./install.sh

# 3. Follow the installation wizard
# - Enter MySQL root password
# - Enter domain name
# - Configure services
```

### Installation Time
⏱️ Approximately 5-10 minutes depending on your server speed

---

## 🎬 Quick Start

### Step 1: Run Main Menu
```bash
vpsmanager
```

### Step 2: Create Your First User

**For VPN (V2Ray):**
```bash
vpsv2ray
# Select: 1 (Add User)
# Username: john
# Days: 30
# Protocol: 1 (VLESS)
```

**For Proxy (SOCKS5):**
```bash
vpssocks5
# Select: 1 (Add User)
# Username: john
# Password: secure123
# Days: 30
```

### Step 3: Get Connection Info
```bash
# Show user details
vpsv2ray
# Select: 4 (Show User Info)
# Copy the config link or QR code
```

### Step 4: Connect from Client
- **V2Ray**: Use v2rayN, v2rayNG, or any V2Ray client
- **OpenVPN**: Use OpenVPN Connect
- **SOCKS5**: Configure in browser or use proxifier

---

## 📚 Usage Guide

### Managing V2Ray VPN
```bash
vpsv2ray
```

**Main Operations:**
1. **Add User**: Create new VPN account
2. **Delete User**: Remove account
3. **List Users**: View all accounts
4. **Show Info**: Get config links & QR codes
5. **Check Expired**: Auto-disable expired accounts

**Supported Protocols:**
- VLESS (fastest)
- VMess (balanced)
- Trojan (stealth)

**Connection Methods:**
- Port 443: TLS encrypted (recommended)
- Port 87: HTTP (fallback)

### Managing OpenVPN
```bash
vpsopenvpn
```

**Main Operations:**
1. **Add User**: Generate .ovpn files
2. **Delete User**: Revoke certificates
3. **List Users**: View all VPN users
4. **Show Info**: Get download links
5. **Active Connections**: See who's online

**Config Types:**
- UDP (Port 1194): Fast, recommended
- TCP (Port 1443): Stable, firewall-friendly

**Download Links:**
```
http://your-domain.com/ovpn/username-udp.ovpn
http://your-domain.com/ovpn/username-tcp.ovpn
```

### Managing SOCKS5 Proxy
```bash
vpssocks5
```

**Main Operations:**
1. **Add User**: Create SOCKS5 account
2. **Delete User**: Remove account
3. **List Users**: View all users
4. **Show Info**: Get connection details
5. **Test Server**: Check if running

**Connection Details:**
```
Server: your-server-ip
Port: 1080
Type: SOCKS5
Username: your-username
Password: your-password
```

**Browser Setup (Firefox):**
```
Settings → Network Settings → Manual Proxy
SOCKS5 Proxy: your-server:1080
✓ Proxy DNS when using SOCKS v5
```

**Testing:**
```bash
curl --socks5 username:password@server:1080 http://ipinfo.io/ip
```

### Managing Squid Proxy
```bash
vpsproxy
```

**Main Operations:**
1. **Add User**: Create HTTP proxy account
2. **Delete User**: Remove account
3. **List Users**: View all users
4. **Show Info**: Get proxy settings
5. **Test Proxy**: Verify connection

**Ports:**
- 3128: Main proxy port
- 8080: Alternative port

**Browser Setup:**
```
HTTP Proxy: your-server:3128
HTTPS Proxy: your-server:3128
Username: your-username
Password: your-password
```

### SSL Certificate Management
```bash
vpsssl
```

**Operations:**
1. **Issue Certificate**: Get new SSL cert
2. **Renew Certificate**: Update existing cert
3. **List Certificates**: View all certs
4. **Auto-Renewal**: Setup automatic renewal

**Requirements:**
- Valid domain name
- DNS pointing to your server
- Port 80 open

### Database Management
```bash
vpsdb
```

**Operations:**
1. **Backup Database**: Create backup
2. **Restore Database**: Restore from backup
3. **List Backups**: View all backups
4. **Optimize Database**: Clean and optimize

**Backup Location:**
```
/root/database_backups/
```

### Statistics Dashboard
```bash
vpsstats
```

**Real-time Monitoring:**
- CPU usage
- RAM usage
- Disk usage
- Network traffic
- Active connections
- Service status

---

## 🎮 Commands Reference

### Main Commands

| Command | Description |
|---------|-------------|
| `vpsmanager` | Main control panel |
| `vpsssh` | SSH user management |
| `vpsproxy` | Squid HTTP proxy management |
| `vpsv2ray` | V2Ray VPN management |
| `vpsopenvpn` | OpenVPN management |
| `vpssocks5` | SOCKS5 proxy management |
| `vpsssl` | SSL certificate management |
| `vpsdb` | Database management |
| `vpsstats` | Statistics dashboard |
| `vpshelp` | Show all commands |

### Quick Actions
```bash
# Restart all services
systemctl restart nginx squid v2ray openvpn-server@server-udp openvpn-server@server-tcp danted

# Check service status
systemctl status nginx squid v2ray openvpn-server@server-udp danted

# View logs
journalctl -u v2ray -f
journalctl -u openvpn-server@server-udp -f
journalctl -u danted -f

# Check ports
ss -tulpn | grep -E ':(22|80|443|1080|1194|1443|3128|8080)'
```

---

## ⚙️ Configuration

### Editing Configurations

**V2Ray:**
```bash
nano /usr/local/etc/v2ray/config.json
systemctl restart v2ray
```

**OpenVPN:**
```bash
nano /etc/openvpn/server/server-udp.conf
nano /etc/openvpn/server/server-tcp.conf
systemctl restart openvpn-server@server-udp
systemctl restart openvpn-server@server-tcp
```

**SOCKS5:**
```bash
nano /etc/danted.conf
systemctl restart danted
```

**Squid:**
```bash
nano /etc/squid/squid.conf
systemctl restart squid
```

**Nginx:**
```bash
nano /etc/nginx/sites-available/your-domain.com
nginx -t
systemctl reload nginx
```

### Changing Ports

Edit the respective configuration files and update firewall rules:
```bash
# Allow new port
ufw allow 8888/tcp

# Remove old port
ufw delete allow 8080/tcp
```

---

## 🐛 Troubleshooting

### Service Won't Start
```bash
# Check service status
systemctl status service-name

# View detailed logs
journalctl -u service-name -n 50

# Test configuration
v2ray test -config=/usr/local/etc/v2ray/config.json
nginx -t
```

### Can't Connect to VPN

**Check 1: Service Running?**
```bash
systemctl status v2ray
systemctl status openvpn-server@server-udp
```

**Check 2: Firewall Open?**
```bash
ufw status
```

**Check 3: Correct Configuration?**
```bash
# Show user config
vpsv2ray
# Select: 4 (Show User Info)
```

### SOCKS5 Authentication Failed

**Check 1: User Exists?**
```bash
vpssocks5
# Select: 3 (List Users)
```

**Check 2: Dante Running?**
```bash
systemctl status danted
```

**Check 3: Test Connection**
```bash
curl --socks5 username:password@localhost:1080 http://ipinfo.io/ip
```

### Database Errors

**Solution 1: Initialize Database**
```bash
# For each service, run initialization:
vpsv2ray → 7 (Initialize Database)
vpsopenvpn → 7 (Initialize Database)
vpssocks5 → 8 (Initialize Database)
```

**Solution 2: Restore from Backup**
```bash
vpsdb
# Select: 2 (Restore Database)
```

### Common Issues

| Problem | Solution |
|---------|----------|
| Port already in use | Change port in config |
| Certificate error | Renew SSL certificate |
| User can't connect | Check expiry date |
| Slow connection | Check server resources |
| Connection drops | Switch to TCP protocol |

---

## 📱 Client Applications

### V2Ray Clients

**Windows:**
- v2rayN: https://github.com/2dust/v2rayN

**Mac:**
- V2RayXS: https://github.com/tzmax/V2RayXS

**Android:**
- v2rayNG: https://play.google.com/store/apps/details?id=com.v2ray.ang

**iOS:**
- Shadowrocket (paid)
- OneClick (free)

### OpenVPN Clients

**Windows/Mac/Linux:**
- OpenVPN Connect: https://openvpn.net/client/

**Android:**
- OpenVPN for Android: https://play.google.com/store/apps/details?id=de.blinkt.openvpn

**iOS:**
- OpenVPN Connect: https://apps.apple.com/app/id590379981

### SOCKS5 Clients

**Windows:**
- Proxifier: https://www.proxifier.com/

**Android:**
- ProxyDroid
- Postern

**iOS:**
- Shadowrocket
- Surge

---

## 🔒 Security Best Practices

1. **Strong Passwords**: Use complex passwords (12+ characters)
2. **Regular Updates**: Keep system and packages updated
3. **Firewall**: Only open necessary ports
4. **SSL/TLS**: Always use encryption when possible
5. **Monitor Logs**: Regularly check for suspicious activity
6. **Backup**: Automated daily backups
7. **Limited Access**: Create separate users, don't share root
8. **Change Defaults**: Change default ports if needed

---

## 📈 Performance Optimization

### For High Traffic Servers
```bash
# Increase file descriptors
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# Optimize TCP settings
cat >> /etc/sysctl.conf << EOF
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
EOF

sysctl -p
```

### Resource Limits

**Recommended Limits:**
- 50 users: 1GB RAM
- 100 users: 2GB RAM
- 500 users: 4GB RAM
- 1000+ users: 8GB+ RAM

---

## 🤝 Contributing

We welcome contributions! Here's how:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Setup
```bash
git clone https://github.com/AndamAziz/vps-pro-maneger.git
cd vps-pro-maneger
# Make your changes
./test.sh  # Run tests
```

---

## 📝 Changelog

### Version 5.0 (Latest)
- ✅ Added SOCKS5 Proxy (Dante server)
- ✅ Improved OpenVPN configs (Android compatible)
- ✅ Fixed proxy authentication
- ✅ Enhanced UI/UX
- ✅ Performance improvements

### Version 4.0
- ✅ Added OpenVPN support
- ✅ Dual port for V2Ray (443 + 87)
- ✅ Database optimization
- ✅ Statistics dashboard

### Version 3.0
- ✅ Added V2Ray VPN
- ✅ Three protocols support
- ✅ QR code generation
- ✅ Auto-expire users

### Version 2.0
- ✅ Added Squid Proxy
- ✅ Dual port support (3128 + 8080)
- ✅ Traffic monitoring

### Version 1.0
- ✅ Initial release
- ✅ SSH user management
- ✅ Basic features

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👨‍💻 Author

**Andam Aziz**
- GitHub: [@AndamAziz](https://github.com/AndamAziz)
- Project: [VPS Manager Pro](https://github.com/AndamAziz/vps-pro-maneger)

---

## 🙏 Acknowledgments

- V2Ray Project
- OpenVPN Community
- Dante SOCKS5 Server
- Squid Proxy
- Ubuntu Community

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/AndamAziz/vps-pro-maneger/issues)
- **Discussions**: [GitHub Discussions](https://github.com/AndamAziz/vps-pro-maneger/discussions)

---

## ⭐ Star History

If you find this project useful, please consider giving it a star! ⭐

---

<div align="center">

**Made with ❤️ by KurdCloud Team**

**Kurdistan • Iraq • 2025**

[⬆ Back to Top](#-vps-manager-pro-v50)

</div>
