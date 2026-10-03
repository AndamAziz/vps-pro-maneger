#!/usr/bin/env bash
#==============================================================================
# Unified user database (Xray + Hysteria2). One user -> credentials for every
# enabled protocol. Stored in $USERS_DB as a JSON array:
#   {name, uuid, password, ss_key, expiry (epoch, 0 = never), created, note}
#==============================================================================

valid_name() { [[ "$1" =~ ^[A-Za-z0-9_-]{2,32}$ ]]; }

user_exists() { jq -e --arg n "$1" 'any(.[]; .name==$n)' "$USERS_DB" >/dev/null 2>&1; }

# users_active -> JSON array of non-expired users
users_active() {
    jq --argjson now "$(date +%s)" '[.[] | select(.expiry==0 or .expiry>$now)]' "$USERS_DB"
}

apply_all() { # push the user list to every installed protocol
    declare -F xray_apply >/dev/null && [ -x /usr/local/bin/xray ] && xray_apply
    declare -F hy2_apply  >/dev/null && [ -f /etc/hysteria/config.yaml ] && hy2_apply
    return 0
}

# user_add NAME [DAYS]
user_add() {
    local name="$1" days="${2:-0}" expiry=0
    valid_name "$name" || { err "Invalid name (2-32 chars: letters, digits, _ or -)."; return 1; }
    user_exists "$name" && { err "User '$name' already exists."; return 1; }
    [[ "$days" =~ ^[0-9]+$ ]] || { err "Days must be a number (0 = unlimited)."; return 1; }
    [ "$days" -gt 0 ] && expiry=$(( $(date +%s) + days * 86400 ))

    jq --arg n "$name" --arg id "$(new_uuid)" --arg pw "$(rand_str 20)" \
       --arg ss "$(openssl rand -base64 16)" --argjson exp "$expiry" --argjson now "$(date +%s)" \
       '. + [{name:$n, uuid:$id, password:$pw, ss_key:$ss, expiry:$exp, created:$now, note:""}]' \
       "$USERS_DB" | json_write "$USERS_DB" || return 1
    log_action "user added: $name (days=$days)"
    ok "User '$name' created$([ "$expiry" -gt 0 ] && echo " (expires $(date -d "@$expiry" '+%F'))" || echo " (no expiry)")"
}

user_del() {
    user_exists "$1" || { err "User '$1' not found."; return 1; }
    jq --arg n "$1" 'map(select(.name!=$n))' "$USERS_DB" | json_write "$USERS_DB" || return 1
    log_action "user deleted: $1"
    ok "User '$1' deleted"
}

# user_renew NAME DAYS  (adds DAYS on top of the remaining time; 0 = unlimited)
user_renew() {
    local name="$1" days="$2" cur now new=0
    user_exists "$name" || { err "User '$name' not found."; return 1; }
    [[ "$days" =~ ^[0-9]+$ ]] || { err "Days must be a number."; return 1; }
    now="$(date +%s)"
    cur="$(jq -r --arg n "$name" '.[]|select(.name==$n)|.expiry' "$USERS_DB")"
    if [ "$days" -gt 0 ]; then
        [ "$cur" -lt "$now" ] && cur="$now"
        new=$(( cur + days * 86400 ))
    fi
    jq --arg n "$name" --argjson e "$new" 'map(if .name==$n then .expiry=$e else . end)' \
        "$USERS_DB" | json_write "$USERS_DB" || return 1
    log_action "user renewed: $name +${days}d"
    ok "User '$name' now $([ "$new" -gt 0 ] && echo "expires $(date -d "@$new" '+%F')" || echo "has no expiry")"
}

user_list() { # user_list [--json]
    if [ "${1:-}" = "--json" ]; then jq . "$USERS_DB"; return; fi
    local count; count="$(jq length "$USERS_DB")"
    if [ "$count" -eq 0 ]; then echo "No users yet."; return; fi
    printf "${BOLD}%-20s %-12s %-10s${NC}\n" "NAME" "EXPIRES" "STATUS"
    jq -r --argjson now "$(date +%s)" '.[] |
        [.name, (if .expiry==0 then "never" else (.expiry|strftime("%Y-%m-%d")) end),
         (if .expiry==0 or .expiry>$now then "active" else "expired" end)] | @tsv' "$USERS_DB" |
    while IFS=$'\t' read -r n e s; do
        local col="$GREEN"; [ "$s" = expired ] && col="$RED"
        printf "%-20s %-12s ${col}%-10s${NC}\n" "$n" "$e" "$s"
    done
}

# Remove expired users from the proxy configs (they are kept in the DB so they
# can be renewed; they simply stop being written to the configs).
users_expire() {
    local n
    n="$(jq --argjson now "$(date +%s)" '[.[]|select(.expiry>0 and .expiry<=$now)]|length' "$USERS_DB")"
    apply_all
    # SSH accounts expire natively through chage; nothing to do here.
    log_action "expiry sweep: $n expired user(s) excluded"
}
