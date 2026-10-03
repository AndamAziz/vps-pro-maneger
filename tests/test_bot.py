"""Telegram bot: inline-button menu and flows (no network; the vpsmanager CLI is stubbed).
Run: BOT_TOKEN=1:x ADMIN_IDS=1 python3 tests/test_bot.py   (needs python-telegram-bot)"""
import asyncio
import json
import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

os.environ.setdefault("BOT_TOKEN", "1:x")
os.environ["ADMIN_IDS"] = "1"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bot"))
import telegram_bot as bot  # noqa: E402

USERS = [{"name": "alice"}, {"name": "bob"}]
CALLS = []


def fake_cli(*args, timeout=180):
    CALLS.append(args)
    if args[:3] == ("user", "list", "--json"):
        return json.dumps(USERS)
    if args[:2] == ("user", "add"):
        return f"✔ User '{args[2]}' created (no expiry)"
    return "OK " + " ".join(args)


bot.run_cli = fake_cli


def make_update(data=None, text=None, uid=1):
    msg = SimpleNamespace(text=text, reply_text=AsyncMock(), reply_document=AsyncMock())
    q = None
    if data is not None:
        q = SimpleNamespace(data=data, answer=AsyncMock(), edit_message_text=AsyncMock(), message=msg)
    return SimpleNamespace(effective_user=SimpleNamespace(id=uid), effective_message=msg, callback_query=q)


def make_ctx(args=None):
    return SimpleNamespace(args=args or [], user_data={})


def run(coro):
    return asyncio.run(coro)


def buttons(markup):
    return [b for row in markup.inline_keyboard for b in row]


class BotTests(unittest.TestCase):
    def setUp(self):
        CALLS.clear()

    def test_menu_has_all_features_and_every_button_works(self):
        data = [b.callback_data for b in buttons(bot.main_menu_markup())]
        self.assertGreaterEqual(len(data), 12)
        for d in data:
            u, c = make_update(d), make_ctx()
            run(bot.on_button(u, c))
            self.assertTrue(u.callback_query.answer.await_count == 1, d)
            self.assertTrue(u.callback_query.edit_message_text.await_count + u.effective_message.reply_text.await_count
                            + u.effective_message.reply_document.await_count >= 1, f"{d} produced no reply")

    def test_callback_data_within_telegram_limit(self):
        n = "a" * 32
        for pfx in ("renewd", "addd", "sshd"):
            for d in (0, 365):
                for b in buttons(bot.days_markup(pfx, n, bot.DAYS_RENEW)):
                    self.assertLessEqual(len(b.callback_data.encode()), 64)

    def test_non_admin_is_rejected_everywhere(self):
        u = make_update("m:status", uid=999)
        run(bot.on_button(u, make_ctx()))
        u.callback_query.answer.assert_awaited_with("⛔ Not authorised.", show_alert=True)
        self.assertEqual(CALLS, [])
        u = make_update(text="/add x", uid=999)
        run(bot.on_text(u, make_ctx()))
        u.effective_message.reply_text.assert_awaited()
        self.assertEqual(CALLS, [])

    def test_status_button_runs_cli(self):
        u = make_update("m:status")
        run(bot.on_button(u, make_ctx()))
        self.assertIn(("status",), CALLS)

    def test_delete_flow_asks_for_confirmation(self):
        u = make_update("pick:del")
        run(bot.on_button(u, make_ctx()))
        kb = u.callback_query.edit_message_text.await_args.kwargs["reply_markup"]
        self.assertEqual([b.callback_data for b in buttons(kb)][:2], ["del:alice", "del:bob"])
        u = make_update("del:alice")
        run(bot.on_button(u, make_ctx()))
        self.assertNotIn(("user", "del", "alice"), CALLS)          # nothing deleted yet
        kb = u.callback_query.edit_message_text.await_args.kwargs["reply_markup"]
        self.assertIn("delok:alice", [b.callback_data for b in buttons(kb)])
        run(bot.on_button(make_update("delok:alice"), make_ctx()))
        self.assertIn(("user", "del", "alice"), CALLS)

    def test_add_user_flow(self):
        c = make_ctx()
        run(bot.on_button(make_update("ask:add"), c))
        self.assertEqual(c.user_data["pending"], "add")
        u = make_update(text="bob2")
        run(bot.on_text(u, c))
        self.assertNotIn("pending", c.user_data)
        kb = u.effective_message.reply_text.await_args.kwargs["reply_markup"]
        self.assertIn("addd:bob2:30", [b.callback_data for b in buttons(kb)])
        u = make_update("addd:bob2:30")
        run(bot.on_button(u, c))
        self.assertIn(("user", "add", "bob2", "30"), CALLS)
        self.assertIn(("user", "links", "bob2"), CALLS)            # links are sent after creation

    def test_invalid_name_keeps_waiting(self):
        c = make_ctx()
        run(bot.on_button(make_update("ask:wg"), c))
        u = make_update(text="bad name; rm -rf /")
        run(bot.on_text(u, c))
        self.assertEqual(c.user_data.get("pending"), "wg")
        self.assertEqual(CALLS, [])

    def test_renew_flow(self):
        run(bot.on_button(make_update("renew:alice"), make_ctx()))
        run(bot.on_button(make_update("renewd:alice:90"), make_ctx()))
        self.assertIn(("user", "renew", "alice", "90"), CALLS)

    def test_ssh_account_flow(self):
        c = make_ctx()
        run(bot.on_button(make_update("ask:ssh"), c))
        run(bot.on_text(make_update(text="bobssh"), c))
        run(bot.on_button(make_update("sshd:bobssh:7"), c))
        self.assertIn(("ssh", "add", "bobssh", "7"), CALLS)

    def test_wireguard_and_ovpn_buttons_create_clients(self):
        c = make_ctx()
        run(bot.on_button(make_update("ask:wg"), c))
        run(bot.on_text(make_update(text="phone1"), c))
        self.assertIn(("wg", "add", "phone1"), CALLS)
        run(bot.on_button(make_update("ask:ovpn"), c))
        run(bot.on_text(make_update(text="laptop1"), c))
        self.assertIn(("ovpn", "add", "laptop1"), CALLS)

    def test_malicious_callback_data_is_ignored(self):
        for d in ("delok:x;reboot", "delok:../../etc", "renewd:alice:abc", "bogus:1", "delok:"):
            run(bot.on_button(make_update(d), make_ctx()))
        self.assertEqual(CALLS, [])

    def test_slash_commands_still_work(self):
        run(bot.add(make_update(text="/add"), make_ctx(["carol", "30"])))
        self.assertIn(("user", "add", "carol", "30"), CALLS)
        u = make_update(text="/start")
        run(bot.start(u, make_ctx()))
        self.assertIsNotNone(u.effective_message.reply_text.await_args.kwargs["reply_markup"])

    def test_video_link_still_downloads(self):
        called = []

        async def fake_download(update, ctx):
            called.append(update.effective_message.text)
        old, bot.download = bot.download, fake_download
        try:
            run(bot.on_text(make_update(text="https://example.com/v"), make_ctx()))
        finally:
            bot.download = old
        self.assertEqual(called, ["https://example.com/v"])

    def test_application_wiring(self):
        """main() registers the commands, the button handler and the text handler."""
        from telegram.ext import CallbackQueryHandler
        added = []
        app = SimpleNamespace(add_handler=added.append, run_polling=lambda **k: None)
        builder = SimpleNamespace(token=lambda t: SimpleNamespace(
            post_init=lambda f: SimpleNamespace(build=lambda: app)))
        old, bot.Application = bot.Application, SimpleNamespace(builder=lambda: builder)
        try:
            bot.main()
        finally:
            bot.Application = old
        self.assertTrue(any(isinstance(h, CallbackQueryHandler) for h in added))
        self.assertGreaterEqual(len(added), 16)

    def test_downloader_uses_the_venv_python_not_PATH(self):
        seen = []

        async def fake_exec(*cmd, **kw):
            seen.append(cmd)
            raise FileNotFoundError("nope")
        u = make_update(text="https://example.com/v")
        note = SimpleNamespace(edit_text=AsyncMock())
        u.effective_message.reply_text = AsyncMock(return_value=note)
        old, bot.asyncio.create_subprocess_exec = bot.asyncio.create_subprocess_exec, fake_exec
        try:
            run(bot.download(u, make_ctx()))
        finally:
            bot.asyncio.create_subprocess_exec = old
        self.assertEqual(seen[0][:3], (sys.executable, "-m", "yt_dlp"))
        self.assertIn("Cannot start the downloader", note.edit_text.await_args.args[0])   # no crash, clear message

    def test_bot_token_never_logged(self):
        import logging
        self.assertGreaterEqual(logging.getLogger("httpx").level, logging.WARNING)

    def test_free_text_shows_menu(self):
        u = make_update(text="hello")
        run(bot.on_text(u, make_ctx()))
        self.assertIsNotNone(u.effective_message.reply_text.await_args.kwargs["reply_markup"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
