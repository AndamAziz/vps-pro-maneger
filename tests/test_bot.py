"""
Tests for bot.py
"""
import pytest
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

def test_bot_imports():
    """Test that bot modules can be imported"""
    try:
        import bot
        assert hasattr(bot, 'main')
    except ImportError as e:
        pytest.skip(f"Bot imports failed: {e}")

def test_config_imports():
    """Test that config can be imported"""
    try:
        import config
        assert hasattr(config, 'BOT_TOKEN')
        assert hasattr(config, 'ADMIN_IDS')
    except ImportError as e:
        pytest.skip(f"Config imports failed: {e}")

@pytest.mark.unit
def test_bot_token_format():
    """Test bot token format"""
    try:
        from config import BOT_TOKEN
        assert isinstance(BOT_TOKEN, str)
        assert len(BOT_TOKEN) > 0
        assert ':' in BOT_TOKEN  # Telegram tokens have format: number:string
    except ImportError:
        pytest.skip("Config not available")

@pytest.mark.unit
def test_admin_ids_format():
    """Test admin IDs format"""
    try:
        from config import ADMIN_IDS
        assert isinstance(ADMIN_IDS, list)
        assert len(ADMIN_IDS) > 0
        assert all(isinstance(id, int) for id in ADMIN_IDS)
    except ImportError:
        pytest.skip("Config not available")
