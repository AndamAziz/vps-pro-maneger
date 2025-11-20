# Deployment Guide

Production deployment strategies for VPS Manager Pro.

## 🚀 Deployment Options

### 1. Single Server (Recommended for < 1000 users)
```bash
curl -sSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/vps-manager-installer.sh | sudo bash
```

### 2. Docker (Recommended for portability)
```bash
git clone https://github.com/AndamAziz/vps-pro-maneger.git
cd vps-pro-maneger
docker-compose up -d
```

### 3. Kubernetes (Recommended for > 5000 users)
```bash
kubectl apply -f kubernetes/
```

### 4. Ansible (Recommended for multiple servers)
```bash
ansible-playbook -i ansible/inventory.ini ansible/deploy.yml
```

---

## 🔧 Configuration

### Environment Variables
```bash
export BOT_TOKEN="your_token"
export ADMIN_IDS="123456789"
export INSTAGRAM_USERNAME="username"
export INSTAGRAM_PASSWORD="password"
```

### Config File
```bash
cp config.example.py config.py
nano config.py
```

---

## 📊 Monitoring

### Health Checks
```bash
# Bot status
vpsbot status

# System resources
bash scripts/monitor.sh

# Logs
vpsbot logs
```

### Prometheus Metrics
Coming soon...

---

## 🔄 Updates

### Manual Update
```bash
cd /opt/vps-manager
git pull origin main
vpsbot restart
```

### Automated Updates
Setup cron job:
```bash
0 2 * * * cd /opt/vps-manager && git pull && vpsbot restart
```

---

## 🛡️ Security Best Practices

1. Change default passwords
2. Use strong credentials
3. Enable firewall
4. Regular backups
5. Monitor logs
6. Update regularly
7. Use SSL/TLS

---

## 📞 Support

For deployment assistance:
- GitHub Issues
- Email: support@kurdcloud.xyz
