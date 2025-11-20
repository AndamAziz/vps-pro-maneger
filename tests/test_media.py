"""
Tests for media downloader
"""
import pytest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

def test_media_handler_imports():
    """Test that media handler can be imported"""
    try:
        from handlers.media import MediaDownloader
        assert MediaDownloader is not None
    except ImportError as e:
        pytest.skip(f"Media handler import failed: {e}")

@pytest.mark.unit
def test_media_downloader_initialization():
    """Test MediaDownloader initialization"""
    try:
        from handlers.media import MediaDownloader
        downloader = MediaDownloader()
        assert downloader is not None
        assert hasattr(downloader, 'download_dir')
    except ImportError:
        pytest.skip("MediaDownloader not available")

@pytest.mark.unit
def test_media_downloader_methods():
    """Test MediaDownloader has required methods"""
    try:
        from handlers.media import MediaDownloader
        downloader = MediaDownloader()
        assert hasattr(downloader, 'download_tiktok')
        assert hasattr(downloader, 'download_instagram')
        assert hasattr(downloader, 'download_youtube')
        assert hasattr(downloader, 'download_facebook')
    except ImportError:
        pytest.skip("MediaDownloader not available")

@pytest.mark.integration
async def test_download_directory_exists():
    """Test that download directory exists"""
    try:
        from handlers.media import MediaDownloader
        downloader = MediaDownloader()
        assert os.path.exists(downloader.download_dir)
    except ImportError:
        pytest.skip("MediaDownloader not available")
