# 🤖 ALL IN ONE BIG BOSS Bot

Telegram bot بۆ داونلۆد کردنی ڤیدیۆ و MP3 لە:
- 📸 Instagram
- 📘 Facebook  
- 🎵 TikTok

## ✨ Features

- ✅ داونلۆد کردنی ڤیدیۆ لە هەر سێ platform
- ✅ گۆڕینی خۆکار بۆ MP3
- ✅ هەردوو فۆرماتەکە دەنێردرێت
- ✅ ئامارگری
- ✅ کوردی و ئینگلیزی

## 📦 Installation
```bash
# 1. Install dependencies
./install.sh

# 2. Configure
nano config.py
# Add your TELEGRAM_TOKEN and SOCIAL_API_KEY

# 3. Start bot
./start.sh

# 4. View logs
tail -f output.log
```

## 🔧 Configuration

Edit `config.py`:
```python
# Get from @BotFather
TELEGRAM_TOKEN = "your_bot_token"

# Get from RapidAPI.com
SOCIAL_API_KEY = "your_rapidapi_key"
```

## 📋 Commands

- `/start` - دەستپێکردن
- `/help` - یارمەتی
- `/stats` - ئامارەکان (admin only)

## 🚀 Usage

1. لینکێک بنێرە لە Instagram/Facebook/TikTok
2. چاوەڕێ بکە
3. هەردوو Video + MP3 وەردەگریت!

## 🛠️ Management
```bash
# Start bot
./start.sh

# Stop bot
./stop.sh

# View logs
tail -f output.log

# Check status
ps aux | grep instagram_bot
```

## 📊 Statistics

Admin دەتوانێت `/stats` بەکاربهێنێت بۆ بینینی:
- کۆی داونلۆدەکان
- ئامار بۆ هەر platform
- ڕێژەی سەرکەوتوویی

## 🔐 Security

- تەنها admin دەتوانێت ئامار ببینێت
- Token-ەکان لە config.py هەڵدەگیرێن
- Log-ەکان لە output.log دەنووسرێن

## 📝 Notes

- پێویستە FFmpeg بۆ گۆڕینی MP3
- پێویستە RapidAPI key
- Bot لە background کاردەکات

## 🆘 Troubleshooting

**Bot کارناکات:**
```bash
# Check logs
tail -f output.log

# Restart
./stop.sh
./start.sh
```

**FFmpeg error:**
```bash
apt-get install ffmpeg
```

**API error:**
- Check config.py tokens
- Verify RapidAPI subscription

## 📞 Support

Created for VPS Manager Pro
