"""
VPS Manager Pro - Example Configuration
Copy this to config_local.py and update with your credentials
"""

import os

# Telegram Bot
BOT_TOKEN = "YOUR_BOT_TOKEN_HERE"
ADMIN_IDS = [123456789]

# Instagram
INSTAGRAM_USERNAME = "your_username"
INSTAGRAM_PASSWORD = "your_password"
INSTAGRAM_SESSION_FILE = "/app/.instagram_session.json"

# Server
DOMAIN = "your-domain.com"

# Database
DB_HOST = "localhost"
DB_PORT = 3306
DB_NAME = "vps_manager"
DB_USER = "vps_admin"
DB_PASSWORD = "your_password"

# Storage
DOWNLOAD_DIR = "/app/downloads"
LOG_DIR = "/app/logs"

# Features
ENABLE_TIKTOK = True
ENABLE_INSTAGRAM = True
ENABLE_YOUTUBE = True
ENABLE_FACEBOOK = True

# Limits
MAX_VIDEO_SIZE = 50 * 1024 * 1024  # 50MB
MAX_PHOTO_SIZE = 10 * 1024 * 1024  # 10MB
DOWNLOAD_TIMEOUT = 300  # 5 minutes
