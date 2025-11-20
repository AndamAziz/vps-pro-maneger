#!/bin/bash

echo "🤖 Installing Telegram Bot..."

# Install system dependencies
apt-get update -qq
apt-get install -y -qq python3 python3-pip ffmpeg

# Install Python packages
pip3 install -r requirements.txt

echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Edit config.py with your tokens"
echo "2. Run: ./start.sh"
