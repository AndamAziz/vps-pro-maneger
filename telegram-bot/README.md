# 🤖 ALL IN ONE BIG BOSS Bot

Telegram bot for downloading videos and converting to MP3 from:
- 📸 Instagram (Posts/Reels)
- 📘 Facebook (Videos)
- 🎵 TikTok (Videos)

## Features

✅ Download video from social media  
✅ Auto convert to MP3  
✅ Send both formats (Video + Audio)  
✅ Kurdish interface  
✅ Statistics tracking  
✅ Admin commands  

## Installation
```bash
# Install dependencies
apt update
apt install -y ffmpeg python3 python3-pip

# Install Python packages
pip3 install -r requirements.txt

# Configure
nano config.py
# Add your TELEGRAM_TOKEN and SOCIAL_API_KEY
```

## Usage

### Start Bot
```bash
pkill -f instagram_bot.py
nohup python3 instagram_bot.py > output.log 2>&1 &
```

### View Logs
```bash
tail -f output.log
```

### Stop Bot
```bash
pkill -f instagram_bot.py
```

## Configuration

Edit `config.py` with your credentials:

1. **TELEGRAM_TOKEN**: Get from [@BotFather](https://t.me/BotFather)
2. **SOCIAL_API_KEY**: Get from [RapidAPI](https://rapidapi.com)

## Commands

- `/start` - Start the bot
- `/stats` - View statistics (admin only)

## How It Works

1. User sends Instagram/Facebook/TikTok link
2. Bot downloads the video
3. Bot converts video to MP3
4. Both files are sent to user

## Requirements

- Python 3.8+
- FFmpeg
- python-telegram-bot
- requests

## Admin

Set `ADMIN_USER_ID` in `instagram_bot.py` to your Telegram user ID to access `/stats` command.

## Notes

- Videos are temporarily saved in `/tmp/`
- Statistics saved in `bot_stats.json`
- Logs saved in `bot.log` and `output.log`

## Troubleshooting

**Bot not starting?**
- Check config.py tokens
- Verify FFmpeg installed: `ffmpeg -version`
- Check logs: `tail -f output.log`

**MP3 conversion fails?**
- Install FFmpeg: `apt install ffmpeg`
- Check video format compatibility

**API errors?**
- Verify RapidAPI key is active
- Check API subscription limits

## Created for VPS Manager Pro
