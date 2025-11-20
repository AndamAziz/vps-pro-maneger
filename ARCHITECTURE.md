# Architecture Documentation

System architecture and design of VPS Manager Pro.

## 🏗️ Overview
```
┌─────────────────────────────────────────────────────────┐
│                    Telegram Users                        │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                  Telegram Bot API                        │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│              bot.py (Main Application)                   │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Command Handlers                                │   │
│  │  - /start, /help, /status, /about               │   │
│  └─────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Message Handler                                 │   │
│  │  - URL Detection & Platform Router              │   │
│  └─────────────────────────────────────────────────┘   │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│         handlers/media.py (Media Downloader)             │
│  ┌──────────────┬──────────────┬──────────────────┐    │
│  │   TikTok     │  Instagram   │  YouTube/FB      │    │
│  │   (yt-dlp)   │ (instagrapi) │   (yt-dlp)      │    │
│  └──────────────┴──────────────┴──────────────────┘    │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                  File System                             │
│  - /app/downloads (temporary storage)                   │
│  - /app/logs (application logs)                         │
└─────────────────────────────────────────────────────────┘
```

## 📦 Components

### 1. bot.py
Main application entry point
- Initializes Telegram bot
- Registers handlers
- Manages bot lifecycle

### 2. handlers/media.py
Media download orchestrator
- Platform detection
- Download management
- File cleanup
- Error handling

### 3. config.py
Configuration management
- Credentials
- Feature flags
- Limits and timeouts

### 4. Database (MySQL)
Data persistence
- User management
- Statistics
- Logs

---

## 🔄 Data Flow

1. User sends URL to bot
2. Bot detects platform
3. Routes to appropriate handler
4. Handler downloads media
5. Bot sends file to user
6. Cleanup temporary files

---

## 🛡️ Security

- Credentials stored in config files
- Session management for Instagram
- SSL/TLS for connections
- Firewall rules
- Regular security updates

---

## 📈 Scalability

- Stateless design
- Async/await for concurrency
- Docker containerization
- Kubernetes ready
- Horizontal scaling possible

---

For deployment, see [INSTALL.md](INSTALL.md)
