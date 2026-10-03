#!/usr/bin/env bash
#==============================================================================
# Telegram bot (admin remote control + optional media downloader)
#==============================================================================

BOT_ENV="$VPSM_ETC/bot.env"
BOT_SVC="vpsm-bot"
BOT_VENV="$VPSM_HOME/venv"

bot_install() {
    require_root
    local token admins
    token="$(ask "Bot token from @BotFather" "")"
    [[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]] || { err "That does not look like a bot token."; return 1; }
    admins="$(ask "Admin Telegram user ID(s), comma separated (from @userinfobot)" "")"
    [[ "$admins" =~ ^[0-9]+(,[0-9]+)*$ ]] || { err "Admin IDs must be numbers."; return 1; }

    info "Installing Python environment..."
    pkg_install python3 python3-venv python3-pip ffmpeg || return 1
    [ -d "$BOT_VENV" ] || python3 -m venv "$BOT_VENV" || { err "venv creation failed"; return 1; }
    "$BOT_VENV/bin/pip" install -q --upgrade pip
    "$BOT_VENV/bin/pip" install -q -r "$VPSM_HOME/bot/requirements.txt" || { err "pip install failed"; return 1; }

    umask 077
    printf 'BOT_TOKEN=%s\nADMIN_IDS=%s\n' "$token" "$admins" > "$BOT_ENV"
    cp "$VPSM_HOME/systemd/vpsm-bot.service" /etc/systemd/system/vpsm-bot.service
    sed -i "s#@HOME@#$VPSM_HOME#g" /etc/systemd/system/vpsm-bot.service
    systemctl daemon-reload; systemctl enable --now "$BOT_SVC" >/dev/null 2>&1
    sleep 2
    svc_active "$BOT_SVC" && ok "Telegram bot is running. Send /start to it." || err "Bot failed to start (journalctl -u $BOT_SVC -n 30)"
    log_action "bot installed"
}

bot_menu() {
    while true; do
        menu_header "🤖 Telegram Bot   [$(svc_state "$BOT_SVC")]"
        echo "  1) Install / reconfigure bot"
        echo "  2) Start     3) Stop     4) Restart"
        echo "  5) View logs"
        echo "  6) Uninstall"
        echo "  0) Back"
        echo -e "$LINE"
        case "$(ask "Choose" "")" in
            1) bot_install; pause ;;
            2) systemctl start "$BOT_SVC"; ok "Started"; pause ;;
            3) systemctl stop "$BOT_SVC"; ok "Stopped"; pause ;;
            4) svc_restart "$BOT_SVC"; pause ;;
            5) journalctl -u "$BOT_SVC" -n 60 --no-pager; pause ;;
            6) if confirm "Remove the bot?" n; then
                   systemctl disable --now "$BOT_SVC" >/dev/null 2>&1
                   rm -f /etc/systemd/system/vpsm-bot.service "$BOT_ENV"; rm -rf "$BOT_VENV"; systemctl daemon-reload; ok "Removed"
               fi; pause ;;
            0|"") return ;;
        esac
    done
}
