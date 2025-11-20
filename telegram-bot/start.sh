#!/bin/bash

# Kill any existing bot process
pkill -f instagram_bot.py

# Start bot in background
nohup python3 instagram_bot.py > output.log 2>&1 &

echo "✅ Bot started!"
echo "📋 View logs: tail -f output.log"
