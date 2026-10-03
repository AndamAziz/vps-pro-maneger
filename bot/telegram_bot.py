#!/usr/bin/env python3
"""VPS Manager Pro - Telegram admin bot.

Every action goes through the `vpsmanager` CLI, so the bot, the terminal menu
and automation scripts always share the same state.
Only the user IDs listed in ADMIN_IDS may use it.
"""
import asyncio
import json
import logging
import os
import re
import subprocess
import sys
import tempfile
from functools import wraps
from pathlib import Path

from telegram import BotCommand, InlineKeyboardButton as Btn, InlineKeyboardMarkup as Markup, Update
from telegram.error import BadRequest
from telegram.ext import Application, CallbackQueryHandler, CommandHandler, ContextTypes, MessageHandler, filters

logging.basicConfig(format="%(asctime)s %(levelname)s %(message)s", level=logging.INFO)
# httpx logs every request URL at INFO - and the Bot API URL contains the bot token
for _noisy in ("httpx", "httpcore"):
    logging.getLogger(_noisy).setLevel(logging.WARNING)
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
            if update.callback_query:
                await update.callback_query.answer("⛔ Not authorised.", show_alert=True)
            elif update.effective_message:
                await update.effective_message.reply_text("⛔ Not authorised.")
            return
        return await fn(update, ctx)
    return wrapper


async def reply_long(update: Update, text: str, pre: bool = True, markup=None):
    chunks = [text[i:i + 3800] for i in range(0, len(text), 3800)] or [""]
    for n, chunk in enumerate(chunks):
        mk = markup if n == len(chunks) - 1 else None
        if pre:
            await update.effective_message.reply_text(
                f"<pre>{chunk.replace('&', '&amp;').replace('<', '&lt;')}</pre>", parse_mode="HTML", reply_markup=mk)
        else:
            await update.effective_message.reply_text(chunk, disable_web_page_preview=True, reply_markup=mk)


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
    "📥 Send any video link to download it (yt-dlp).\n\n"
    "👇 Or just use the buttons below (/menu)."
)

# ---- buttons

HOME = [Btn("🏠 Menu", callback_data="m:home")]
DAYS_USER = (("♾ Unlimited", 0), ("7", 7), ("30", 30), ("90", 90), ("365", 365))
DAYS_RENEW = (("7", 7), ("30", 30), ("90", 90), ("365", 365), ("♾ Unlimited", 0))
DAYS_SSH = (("7", 7), ("30", 30), ("90", 90), ("365", 365))


def home_markup() -> Markup:
    return Markup([HOME])


def main_menu_markup() -> Markup:
    rows = [
        [("📊 Status", "m:status"), ("👥 Users", "m:users")],
        [("➕ Add user", "ask:add"), ("🗑 Delete user", "pick:del")],
        [("🔄 Renew user", "pick:renew"), ("🔗 Links", "pick:links")],
        [("📈 Traffic", "m:usage"), ("💾 Backup", "m:backup")],
        [("🛡 WireGuard", "ask:wg"), ("🔒 OpenVPN", "ask:ovpn")],
        [("🔐 SSH account", "ask:ssh"), ("🔌 Open ports", "m:ports")],
    ]
    return Markup([[Btn(t, callback_data=d) for t, d in row] for row in rows])


def user_names() -> list:
    try:
        data = json.loads(run_cli("user", "list", "--json"))
        return [u["name"] for u in data if NAME_RE.match(str(u.get("name", "")))]
    except (ValueError, TypeError, KeyError):
        return []


def names_markup(action: str, names: list) -> Markup:
    rows, row = [], []
    for n in names[:90]:
        row.append(Btn(n, callback_data=f"{action}:{n}"))
        if len(row) == 2:
            rows.append(row)
            row = []
    if row:
        rows.append(row)
    rows.append(HOME)
    return Markup(rows)


def days_markup(prefix: str, name: str, options) -> Markup:
    rows = [[Btn(f"{label} days" if d else label, callback_data=f"{prefix}:{name}:{d}") for label, d in options]]
    return Markup(rows + [HOME])


async def show(update: Update, text: str, markup=None):
    """Edit the message the button sits on (fall back to a new message)."""
    q = update.callback_query
    try:
        await q.edit_message_text(text, parse_mode="HTML", reply_markup=markup)
    except BadRequest as e:
        if "not modified" not in str(e).lower():
            await q.message.reply_text(text, parse_mode="HTML", reply_markup=markup)


@admin_only
async def start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    ctx.user_data.pop("pending", None)
    await update.effective_message.reply_text(HELP, parse_mode="HTML", reply_markup=main_menu_markup())


def valid_name(args, idx=0):
    return len(args) > idx and NAME_RE.match(args[idx])


# ---- actions (shared by the /commands and the buttons)

async def do_status(update):
    await reply_long(update, run_cli("status"), markup=home_markup())


async def do_users(update):
    await reply_long(update, run_cli("user", "list"), markup=home_markup())


async def do_usage(update):
    await reply_long(update, run_cli("user", "usage"), markup=home_markup())


async def do_ports(update):
    await reply_long(update, run_cli("ports"), markup=home_markup())


async def do_backup(update):
    path = run_cli("backup").splitlines()[-1].strip()
    if path.endswith(".tar.gz") and Path(path).is_file():
        with open(path, "rb") as fh:
            await update.effective_message.reply_document(fh, filename=Path(path).name, reply_markup=home_markup())
    else:
        await reply_long(update, path, markup=home_markup())


async def do_add(update, name, days):
    out = run_cli("user", "add", name, str(days))
    await reply_long(update, out, markup=None if "created" in out else home_markup())
    if "created" in out:
        await reply_long(update, run_cli("user", "links", name), pre=False, markup=home_markup())


async def do_del(update, name):
    await reply_long(update, run_cli("user", "del", name), markup=home_markup())


async def do_renew(update, name, days):
    await reply_long(update, run_cli("user", "renew", name, str(days)), markup=home_markup())


async def do_links(update, name):
    await reply_long(update, run_cli("user", "links", name), pre=False, markup=home_markup())


async def do_ssh(update, name, days):
    await reply_long(update, run_cli("ssh", "add", name, str(days)), markup=home_markup())


async def send_client_files(update, cli_args, name, file_tpls):
    """Create a VPN client with the CLI and send the generated file(s)."""
    out = run_cli(*cli_args, name)
    files = [Path(t.format(name=name)) for t in file_tpls]
    files = [f for f in files if f.is_file()]
    if not files:
        return await reply_long(update, out, markup=home_markup())
    for n, f in enumerate(files):
        with open(f, "rb") as fh:
            await update.effective_message.reply_document(
                fh, filename=f.name, reply_markup=home_markup() if n == len(files) - 1 else None)


async def do_wg(update, name):
    await send_client_files(update, ("wg", "add"), name, ["/etc/vps-manager/wireguard/{name}.conf"])


async def do_ovpn(update, name):
    await send_client_files(update, ("ovpn", "add"), name, [
        "/etc/vps-manager/openvpn/{name}.ovpn", "/etc/vps-manager/openvpn/{name}-udp.ovpn",
        "/etc/vps-manager/openvpn/{name}-tcp.ovpn"])


# ---- /commands

@admin_only
async def status(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await do_status(update)


@admin_only
async def users(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await do_users(update)


@admin_only
async def usage(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await do_usage(update)


@admin_only
async def backup(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await do_backup(update)


@admin_only
async def add(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    a = ctx.args
    if not valid_name(a):
        return await update.effective_message.reply_text("Usage: /add <name> [days]")
    await do_add(update, a[0], a[1] if len(a) > 1 and a[1].isdigit() else "0")


@admin_only
async def delete(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not valid_name(ctx.args):
        return await update.effective_message.reply_text("Usage: /del <name>")
    await do_del(update, ctx.args[0])


@admin_only
async def renew(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    a = ctx.args
    if not valid_name(a) or len(a) < 2 or not a[1].isdigit():
        return await update.effective_message.reply_text("Usage: /renew <name> <days>")
    await do_renew(update, a[0], a[1])


@admin_only
async def links(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not valid_name(ctx.args):
        return await update.effective_message.reply_text("Usage: /links <name>")
    await do_links(update, ctx.args[0])


@admin_only
async def wg(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not valid_name(ctx.args):
        return await update.effective_message.reply_text("Usage: /wg <name>")
    await do_wg(update, ctx.args[0])


@admin_only
async def ovpn(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not valid_name(ctx.args):
        return await update.effective_message.reply_text("Usage: /ovpn <name>")
    await do_ovpn(update, ctx.args[0])


@admin_only
async def ssh_account(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    a = ctx.args
    if not valid_name(a):
        return await update.effective_message.reply_text("Usage: /ssh <name> [days]")
    await do_ssh(update, a[0], a[1] if len(a) > 1 and a[1].isdigit() else "30")


# ---- buttons

ASK_TEXT = {
    "add": "➕ <b>New user</b> (all protocols)",
    "wg": "🛡 <b>New WireGuard client</b>",
    "ovpn": "🔒 <b>New OpenVPN client</b> (UDP + TCP)",
    "ssh": "🔐 <b>New SSH tunnel account</b>",
}
PICK_TEXT = {"del": "🗑 Delete which user?", "renew": "🔄 Renew which user?", "links": "🔗 Links of which user?"}
SIMPLE = {"status": do_status, "users": do_users, "usage": do_usage, "ports": do_ports, "backup": do_backup}


@admin_only
async def on_button(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    parts = (q.data or "").split(":")
    kind, arg = parts[0], parts[1] if len(parts) > 1 else ""
    name = arg if NAME_RE.match(arg) else ""
    days = parts[2] if len(parts) > 2 and parts[2].isdigit() else ""

    if kind == "m":
        ctx.user_data.pop("pending", None)
        if arg == "home":
            return await show(update, HELP, main_menu_markup())
        if arg in SIMPLE:
            return await SIMPLE[arg](update)
    elif kind == "pick" and arg in PICK_TEXT:
        names = user_names()
        if not names:
            return await show(update, "No users yet.", home_markup())
        return await show(update, PICK_TEXT[arg], names_markup(arg, names))
    elif kind == "ask" and arg in ASK_TEXT:
        ctx.user_data["pending"] = arg
        hint = "\n\nSend the name now (2-32 letters, digits, <code>-</code> or <code>_</code>)."
        return await show(update, ASK_TEXT[arg] + hint, home_markup())
    elif kind == "del" and name:
        return await show(update, f"Delete user <b>{name}</b>?",
                          Markup([[Btn("✅ Yes, delete", callback_data=f"delok:{name}"), Btn("❌ No", callback_data="m:home")]]))
    elif kind == "delok" and name:
        return await do_del(update, name)
    elif kind == "renew" and name:
        return await show(update, f"Extend <b>{name}</b> by:", days_markup("renewd", name, DAYS_RENEW))
    elif kind == "renewd" and name and days:
        return await do_renew(update, name, days)
    elif kind == "links" and name:
        return await do_links(update, name)
    elif kind == "addd" and name and days:
        return await do_add(update, name, days)
    elif kind == "sshd" and name and days:
        return await do_ssh(update, name, days)
    log.warning("Unknown button: %r", q.data)


async def handle_pending(update: Update, ctx: ContextTypes.DEFAULT_TYPE, action: str, text: str):
    """A name was typed after pressing an 'Add ...' button."""
    name = text.strip()
    if not NAME_RE.match(name):
        return await update.effective_message.reply_text(
            "❌ Use 2-32 letters, digits, - or _. Send the name again, or press 🏠 Menu.", reply_markup=home_markup())
    ctx.user_data.pop("pending", None)
    if action == "add":
        return await update.effective_message.reply_text(
            f"Valid for how long? (user <b>{name}</b>)", parse_mode="HTML", reply_markup=days_markup("addd", name, DAYS_USER))
    if action == "ssh":
        return await update.effective_message.reply_text(
            f"Valid for how long? (SSH account <b>{name}</b>)", parse_mode="HTML",
            reply_markup=days_markup("sshd", name, DAYS_SSH))
    if action == "wg":
        return await do_wg(update, name)
    if action == "ovpn":
        return await do_ovpn(update, name)


@admin_only
async def on_text(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    text = update.effective_message.text or ""
    pending = ctx.user_data.get("pending")
    if pending and not URL_RE.search(text):
        return await handle_pending(update, ctx, pending, text)
    if URL_RE.search(text):
        return await download(update, ctx)
    await update.effective_message.reply_text("Use the buttons 👇", reply_markup=main_menu_markup())


async def download(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    m = URL_RE.search(update.effective_message.text or "")
    if not m:
        return
    url = m.group(0)
    note = await update.effective_message.reply_text("⏳ Downloading...")
    with tempfile.TemporaryDirectory() as tmp:
        # the venv's yt-dlp (systemd does not put the venv's bin directory on PATH)
        cmd = [sys.executable, "-m", "yt_dlp", "--no-playlist", "--max-filesize", "49M",
               "-f", "b[filesize<49M]/bv*[filesize<40M]+ba/b", "--merge-output-format", "mp4",
               "-o", f"{tmp}/%(title).80s.%(ext)s", url]
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
        except OSError as e:
            return await note.edit_text(f"❌ Cannot start the downloader: {e}")
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
            await update.effective_message.reply_document(fh, filename=f.name)
        await note.delete()


COMMANDS = [
    ("menu", "Show the button menu"), ("status", "Server & service status"), ("users", "List users"),
    ("usage", "Traffic per user"), ("backup", "Send configuration backup"),
    ("add", "/add <name> [days]"), ("del", "/del <name>"), ("renew", "/renew <name> <days>"),
    ("links", "/links <name>"), ("wg", "/wg <name>"), ("ovpn", "/ovpn <name>"), ("ssh", "/ssh <name> [days]"),
]


async def post_init(app: Application):
    try:
        await app.bot.set_my_commands([BotCommand(c, d) for c, d in COMMANDS])
    except Exception as e:  # cosmetic only
        log.warning("set_my_commands failed: %s", e)


def main():
    if not ADMINS:
        raise SystemExit("ADMIN_IDS is empty - refusing to start an unprotected bot.")
    app = Application.builder().token(TOKEN).post_init(post_init).build()
    for name, fn in [("start", start), ("help", start), ("menu", start), ("status", status), ("users", users),
                     ("add", add), ("del", delete), ("renew", renew), ("links", links), ("usage", usage),
                     ("backup", backup), ("wg", wg), ("ovpn", ovpn), ("ssh", ssh_account)]:
        app.add_handler(CommandHandler(name, fn))
    app.add_handler(CallbackQueryHandler(on_button))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, on_text))
    log.info("Bot started for admins: %s", sorted(ADMINS))
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
