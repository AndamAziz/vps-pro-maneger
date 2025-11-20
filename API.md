# API Documentation

VPS Manager Pro Bot API reference.

## 🤖 Bot Commands

### User Commands

#### /start
Start the bot and show welcome message.

**Response**: Welcome message with features list

#### /help
Show help menu with usage instructions.

**Response**: Detailed help text

#### /status
Show bot and server statistics.

**Response**: 
- Bot status
- System resources (CPU, Memory, Disk)
- Service status

#### /about
Show bot information.

**Response**: Version, developer info, links

---

## 📥 Media Download

### Supported Platforms

#### TikTok
**Format**: Send TikTok video URL
**Example**: `https://www.tiktok.com/@user/video/123456789`
**Response**: Video file (no watermark)

#### Instagram
**Formats**:
- Posts: `https://www.instagram.com/p/ABC123/`
- Reels: `https://www.instagram.com/reel/ABC123/`
- IGTV: `https://www.instagram.com/tv/ABC123/`

**Response**: 
- Photos: Image file(s)
- Videos: Video file
- Albums: Multiple files

#### YouTube
**Format**: `https://www.youtube.com/watch?v=ABC123`
**Response**: Video file (up to 720p)

#### Facebook  
**Format**: `https://www.facebook.com/watch/?v=123456`
**Response**: Video file

---

## 🔌 Python API

### MediaDownloader Class
```python
from handlers.media import MediaDownloader

# Initialize
downloader = MediaDownloader()

# Download TikTok
result = await downloader.download_tiktok(url)

# Download Instagram
result = await downloader.download_instagram(url)

# Download YouTube
result = await downloader.download_youtube(url)

# Download Facebook
result = await downloader.download_facebook(url)
```

### Response Format
```python
{
    'success': bool,
    'file': str,  # Path to downloaded file
    'type': str,  # 'video' or 'photo'
    'title': str,  # Media title
    'platform': str  # 'tiktok', 'instagram', etc.
}
```

### Error Response
```python
{
    'success': False,
    'error': str  # Error message
}
```

---

## 🔒 Configuration

See [config.example.py](config.example.py) for all configuration options.

---

## 📝 Examples

### Basic Usage
```python
import asyncio
from handlers.media import MediaDownloader

async def main():
    downloader = MediaDownloader()
    
    # Download TikTok video
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

For more information, see the [README.md](README.md).
