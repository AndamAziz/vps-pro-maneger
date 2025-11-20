# API Documentation

VPS Manager Pro Bot API reference.

## 🤖 Bot Commands

### /start
Start the bot and show welcome message.

### /help
Show detailed help menu.

### /status
Show bot and server statistics including:
- Bot status
- CPU, Memory, Disk usage
- Service status

### /about
Show bot information, version, and links.

---

## 📥 Media Download

### Supported Platforms

#### TikTok
**URL Format**: `https://www.tiktok.com/@user/video/123456789`
**Response**: Video file without watermark

#### Instagram
**URL Formats**:
- Posts: `https://www.instagram.com/p/ABC123/`
- Reels: `https://www.instagram.com/reel/ABC123/`
- IGTV: `https://www.instagram.com/tv/ABC123/`

**Response**: Photos, videos, or albums

#### YouTube
**URL Format**: `https://www.youtube.com/watch?v=ABC123`
**Response**: Video file (max 720p)

#### Facebook
**URL Format**: `https://www.facebook.com/watch/?v=123456`
**Response**: Video file

---

## 🔌 Python API

### MediaDownloader Class
```python
from handlers.media import MediaDownloader

downloader = MediaDownloader()

# TikTok
result = await downloader.download_tiktok(url)

# Instagram
result = await downloader.download_instagram(url)

# YouTube
result = await downloader.download_youtube(url)

# Facebook
result = await downloader.download_facebook(url)
```

### Response Format

Success:
```python
{
    'success': True,
    'file': '/path/to/file',
    'type': 'video',  # or 'photo'
    'title': 'Media title',
    'platform': 'tiktok'
}
```

Error:
```python
{
    'success': False,
    'error': 'Error message'
}
```

---

## 📝 Examples

### Basic Usage
```python
import asyncio
from handlers.media import MediaDownloader

async def main():
    downloader = MediaDownloader()
    result = await downloader.download_tiktok(
        "https://www.tiktok.com/@user/video/123"
    )
    
    if result['success']:
        print(f"Downloaded: {result['file']}")
    else:
        print(f"Error: {result['error']}")

asyncio.run(main())
```

---

For complete documentation, see [README.md](README.md)
