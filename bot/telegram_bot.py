#!/usr/bin/env python3
"""VPS Manager Pro - Telegram admin bot.

Every action goes through the `vpsmanager` CLI, so the bot, the terminal menu
and automation scripts always share the same state.
Only the user IDs listed in ADMIN_IDS may use it.
"""
import asyncio
import logging
import os
import re
import subprocess
import tempfile
from functools import wraps
from pathlib import Path

from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes, MessageHandler, filters

logging.basicConfig(format="%(asctime)s %(levelname)s %(message)s", level=logging.INFO)
log = logging.getLogger("vpsm-bot")

TOKEN = os.environ["BOT_TOKEN"]
ADMINS = {int(x) for x in os.environ.get("ADMIN_IDS", "").split(",") if x.strip().isdigit()}
CLI = "/usr/local/bin/vpsmanager"
NAME_RE = re.compile(r"^[A-Za-z0-9_-]{2,32}$")
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
URL_RE = re.compile(r"https?://\S+")
MAX_UPLOAD = 49 * 1024 * 1024  # Bot API limit is 50 MB


def run_cli(*args: str, timeout: int = 180) -> str:
    """Run the vpsmanager CLI and return cleaned output."""
    try:
        res = subprocess.run([CLI, *args], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return "Command timed out."
    return ANSI_RE.sub("", (res.stdout + res.stderr).strip()) or "(no output)"


def admin_only(fn):
    @wraps(fn)
    async def wrapper(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        uid = update.effective_user.id if update.effective_user else 0
        if uid not in ADMINS:
            log.warning("Rejected user %s", uid)
            if update.message:
                await update.message.reply_text("⛔ Not authorised.")
            return
        return await fn(update, ctx)
    return wrapper


async def reply_long(update: Update, text: str, pre: bool = True):
    for i in range(0, len(text), 3800):
        chunk = text[i:i + 3800]
        if pre:
            await update.message.reply_text(f"<pre>{chunk.replace('&', '&amp;').replace('<', '&lt;')}</pre>", parse_mode="HTML")
        else:
            await update.message.reply_text(chunk, disable_web_page_preview=True)


HELP = (
    "🚀 <b>VPS Manager Pro</b>\n\n"
    "/status – server &amp; service status\n"
    "/users – list users\n"
    "/add &lt;name&gt; [days] – create user (all protocols)\n"
    "/del &lt;name&gt; – delete user\n"
    "/renew &lt;name&gt; &lt;days&gt; – extend user\n"
    "/links &lt;name&gt; – share links\n"
    "/usage – traffic per user\n"
    "/backup – send configuration backup\n"
    "/wg &lt;name&gt; – new WireGuard client (config file)\n"
    "/ovpn &lt;name&gt; – new OpenVPN client (.ovpn)\n"
    "/ssh &lt;name&gt; [days] – new SSH tunnel account\n\n"
    "📥 Send any video link to download it (yt-dlp)."
)


@admin_only
async def start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(HELP, parse_mode="HTML")


@admin_only
async def status(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await reply_long(update, run_cli("status"))


@admin_only
async def users(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await reply_long(update, run_cli("user", "list"))


def valid_name(args, idx=0):
    return len(args) > idx and NAME_RE.match(args[idx])


@admin_only
async def add(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    a = ctx.args
    if not valid_name(a):
        return await update.message.reply_text("Usage: /add <name> [days]")
    days = a[1] if len(a) > 1 and a[1].isdigit() else "0"
    out = run_cli("user", "add", a[0], days)
    await reply_long(update, out)
    if "created" in out:
        await reply_long(update, run_cli("user", "links", a[0]), pre=False)


@admin_only
async def delete(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not valid_name(ctx.args):
        return await update.message.reply_text("Usage: /del <name>")
    await reply_long(update, run_cli("user", "del", ctx.args[0]))


@admin_only
async def renew(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    a = ctx.args
    if not valid_name(a) or len(a) < 2 or not a[1].isdigit():
        return await update.message.reply_text("Usage: /renew <name> <days>")
    await reply_long(update, run_cli("user", "renew", a[0], a[1]))


@admin_only
async def links(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not valid_name(ctx.args):
        return await update.message.reply_text("Usage: /links <name>")
    await reply_long(update, run_cli("user", "links", ctx.args[0]), pre=False)


@admin_only
async def usage(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await reply_long(update, run_cli("user", "usage"))


@admin_only
async def backup(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    path = run_cli("backup").splitlines()[-1].strip()
    if path.endswith(".tar.gz") and Path(path).is_file():
        with open(path, "rb") as fh:
            await update.message.reply_document(fh, filename=Path(path).name)
    else:
        await reply_long(update, path)


async def send_file_cmd(update, ctx, cli_args, file_tpl, label):
    if not valid_name(ctx.args):
        return await update.message.reply_text(f"Usage: /{label} <name>")
    name = ctx.args[0]
    out = run_cli(*cli_args, name)
    f = Path(file_tpl.format(name=name))
    if f.is_file():
        with open(f, "rb") as fh:
            await update.message.reply_document(fh, filename=f.name)
    else:
        await reply_long(update, out)


@admin_only
async def wg(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await send_file_cmd(update, ctx, ("wg", "add"), "/etc/vps-manager/wireguard/{name}.conf", "wg")


@admin_only
async def ovpn(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await send_file_cmd(update, ctx, ("ovpn", "add"), "/etc/vps-manager/openvpn/{name}.ovpn", "ovpn")


@admin_only
async def ssh_account(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    a = ctx.args
    if not valid_name(a):
        return await update.message.reply_text("Usage: /ssh <name> [days]")
    days = a[1] if len(a) > 1 and a[1].isdigit() else "30"
    await reply_long(update, run_cli("ssh", "add", a[0], days))


@admin_only
async def download(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    m = URL_RE.search(update.message.text or "")
    if not m:
        return
    url = m.group(0)
    note = await update.message.reply_text("⏳ Downloading...")
    with tempfile.TemporaryDirectory() as tmp:
        cmd = ["yt-dlp", "--no-playlist", "--max-filesize", "49M", "-f", "b[filesize<49M]/bv*[filesize<40M]+ba/b",
               "--merge-output-format", "mp4", "-o", f"{tmp}/%(title).80s.%(ext)s", url]
        proc = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
        try:
            out, _ = await asyncio.wait_for(proc.communicate(), timeout=600)
        except asyncio.TimeoutError:
            proc.kill()
            return await note.edit_text("❌ Download timed out.")
        files = [p for p in Path(tmp).iterdir() if p.is_file()]
        if proc.returncode != 0 or not files:
            return await note.edit_text("❌ Download failed:\n" + out.decode(errors="ignore")[-400:])
        f = max(files, key=lambda p: p.stat().st_size)
        if f.stat().st_size > MAX_UPLOAD:
            return await note.edit_text("❌ File is larger than Telegram's 50 MB bot limit.")
        with open(f, "rb") as fh:
            await update.message.reply_document(fh, filename=f.name)
        await note.delete()


def main():
    if not ADMINS:
        raise SystemExit("ADMIN_IDS is empty - refusing to start an unprotected bot.")
    app = Application.builder().token(TOKEN).build()
    for name, fn in [("start", start), ("help", start), ("status", status), ("users", users), ("add", add),
                     ("del", delete), ("renew", renew), ("links", links), ("usage", usage),
                     ("backup", backup), ("wg", wg), ("ovpn", ovpn), ("ssh", ssh_account)]:
        app.add_handler(CommandHandler(name, fn))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, download))
    log.info("Bot started for admins: %s", sorted(ADMINS))
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
