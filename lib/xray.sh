#!/usr/bin/env bash
#==============================================================================
# Xray-core: VLESS+Reality (Vision), VLESS-WS, VMess-WS, Trojan, Shadowsocks-2022
# The Xray config is regenerated from inbounds + users.json on every change.
#==============================================================================

XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_INB="$VPSM_ETC/xray-inbounds.json"
XRAY_API_PORT=10085
XRAY_INSTALL_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

xray_installed() { [ -x "$XRAY_BIN" ]; }

xray_require() {
    xray_installed || { err "Xray is not installed. Use: Xray menu → Install."; return 1; }
}

xray_install() {
    require_root
    need_cmd curl; need_cmd jq; need_cmd openssl
    info "Installing Xray-core (official installer)..."
    local script
    script="$(curl -fsSL "$XRAY_INSTALL_URL")" || { err "Cannot download the Xray installer."; return 1; }
    # '-u root' lets Xray read Let's Encrypt keys without permission tweaks
    bash -c "$script" @ install -u root >/dev/null 2>&1 || { err "Xray installation failed."; return 1; }
    xray_installed || { err "Xray binary not found after install."; return 1; }
    [ -s "$XRAY_INB" ] || { echo '[]' > "$XRAY_INB"; chmod 600 "$XRAY_INB"; }
    systemctl enable xray >/dev/null 2>&1
    ok "Xray $("$XRAY_BIN" version | head -1 | awk '{print $2}') installed"
    log_action "xray installed"
}

xray_update() {
    xray_require || return 1
    info "Updating Xray-core..."
    local script
    script="$(curl -fsSL "$XRAY_INSTALL_URL")" || { err "Download failed."; return 1; }
    bash -c "$script" @ install -u root >/dev/null 2>&1 && ok "Xray updated: $("$XRAY_BIN" version | head -1 | awk '{print $2}')"
    xray_apply
}

xray_uninstall() {
    local script
    script="$(curl -fsSL "$XRAY_INSTALL_URL")" && bash -c "$script" @ remove --purge >/dev/null 2>&1
    rm -f "$XRAY_INB"
    ok "Xray removed"
    log_action "xray uninstalled"
}

#---- config generation --------------------------------------------------------

xray_build_config() {
    local tmpu bt=true
    [ "$(setting_get block_bittorrent)" = 0 ] && bt=false
    tmpu="$(mktemp)"; users_active > "$tmpu"
    jq -n --slurpfile ib "$XRAY_INB" --slurpfile us "$tmpu" \
          --argjson bt "$bt" --argjson apiport "$XRAY_API_PORT" '
      ($us[0]) as $u | ($ib[0]) as $I |
      def sniff: {enabled:true, destOverride:["http","tls","quic"]};
      def tlsset($i; $alpn): {security:"tls",
          tlsSettings:{certificates:[{certificateFile:$i.cert, keyFile:$i.key}], alpn:$alpn}};
      def wsset($i): {network:"ws", wsSettings:({path:$i.path}
          + (if ($i.host // "") != "" then {headers:{Host:$i.host}} else {} end))};
      def inbound($i):
        if $i.type=="reality" then
          {tag:$i.tag, listen:"0.0.0.0", port:$i.port, protocol:"vless",
           settings:{clients:[$u[]|{id:.uuid, email:.name, flow:"xtls-rprx-vision"}], decryption:"none"},
           streamSettings:{network:"tcp", security:"reality",
             realitySettings:{show:false, dest:($i.sni+":443"), xver:0, serverNames:[$i.sni],
                              privateKey:$i.privateKey, shortIds:[$i.shortId]}},
           sniffing:sniff}
        elif $i.type=="vless-ws" then
          {tag:$i.tag, listen:"0.0.0.0", port:$i.port, protocol:"vless",
           settings:{clients:[$u[]|{id:.uuid, email:.name}], decryption:"none"},
           streamSettings:(wsset($i) + (if $i.tls then tlsset($i; ["http/1.1"]) else {security:"none"} end)),
           sniffing:sniff}
        elif $i.type=="vmess-ws" then
          {tag:$i.tag, listen:"0.0.0.0", port:$i.port, protocol:"vmess",
           settings:{clients:[$u[]|{id:.uuid, email:.name, alterId:0}]},
           streamSettings:(wsset($i) + (if $i.tls then tlsset($i; ["http/1.1"]) else {security:"none"} end)),
           sniffing:sniff}
        elif $i.type=="trojan" then
          {tag:$i.tag, listen:"0.0.0.0", port:$i.port, protocol:"trojan",
           settings:{clients:[$u[]|{password:.password, email:.name}]},
           streamSettings:({network:"tcp"} + tlsset($i; ["h2","http/1.1"])),
           sniffing:sniff}
        elif $i.type=="ss2022" then
          {tag:$i.tag, listen:"0.0.0.0", port:$i.port, protocol:"shadowsocks",
           settings:{method:"2022-blake3-aes-128-gcm", password:$i.serverKey, network:"tcp,udp",
                     clients:[$u[]|{password:.ss_key, email:.name}]},
           sniffing:sniff}
        else empty end;
      {
        log:{loglevel:"warning"},
        stats:{},
        api:{tag:"api", services:["StatsService"]},
        policy:{levels:{"0":{statsUserUplink:true, statsUserDownlink:true}}},
        inbounds:(
          [{tag:"api", listen:"127.0.0.1", port:$apiport, protocol:"dokodemo-door",
            settings:{address:"127.0.0.1"}}]
          + (if ($u|length)>0 then [$I[]|inbound(.)] else [] end)),
        outbounds:[{tag:"direct", protocol:"freedom"}, {tag:"block", protocol:"blackhole"}],
        routing:{domainStrategy:"IPIfNonMatch", rules:(
          [{type:"field", inboundTag:["api"], outboundTag:"api"},
           {type:"field", ip:["geoip:private"], outboundTag:"block"}]
          + (if $bt then [{type:"field", protocol:["bittorrent"], outboundTag:"block"}] else [] end))}
      }'
    local rc=$?
    rm -f "$tmpu"
    return $rc
}

xray_apply() {
    xray_installed || return 0
    [ -s "$XRAY_INB" ] || echo '[]' > "$XRAY_INB"
    local tmp; tmp="$(mktemp --suffix=.json)"   # Xray picks the parser from the extension
    if ! xray_build_config > "$tmp"; then err "Could not build Xray config."; rm -f "$tmp"; return 1; fi
    if ! "$XRAY_BIN" run -test -config "$tmp" >/dev/null 2>&1; then
        err "Generated Xray config failed validation:"
        "$XRAY_BIN" run -test -config "$tmp" 2>&1 | tail -5
        rm -f "$tmp"; return 1
    fi
    mkdir -p "$(dirname "$XRAY_CONF")"
    install -m 640 "$tmp" "$XRAY_CONF"; rm -f "$tmp"
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray && ok "Xray configuration applied" || { err "Xray failed to start (journalctl -u xray -n 30)"; return 1; }
}

#---- inbounds -------------------------------------------------------------------

inb_add() { # inb_add JSON
    jq --argjson n "$1" '. + [$n]' "$XRAY_INB" | json_write "$XRAY_INB"
}

xray_inbound_exists() { jq -e --arg t "$1" 'any(.[]; .tag==$t)' "$XRAY_INB" >/dev/null 2>&1; }

xray_gen_reality_keys() { # sets R_PRIV R_PUB
    local out
    out="$("$XRAY_BIN" x25519 2>/dev/null)"
    R_PRIV="$(echo "$out" | awk -F': *' 'tolower($1) ~ /^private ?key$/ {print $2; exit}')"
    R_PUB="$(echo "$out" | awk -F': *' 'tolower($1) ~ /^(public ?key|password)$/ {print $2; exit}')"
    [ -n "$R_PRIV" ] && [ -n "$R_PUB" ]
}

# xray_add_inbound TYPE PORT [DOMAIN] [EXTRA]
#   reality  : EXTRA = SNI to impersonate (default www.microsoft.com)
#   *-ws     : DOMAIN = TLS domain ('' = plain WS), EXTRA = path
xray_add_inbound() {
    xray_require || return 1
    local type="$1" port="$2" domain="${3:-}" extra="${4:-}" tag json paths cert key
    valid_port "$port" || { err "Invalid port."; return 1; }
    tag="${type}-${port}"
    port_used_by_other "$port" && { err "Port $port is already used by another service."; return 1; }
    xray_inbound_exists "$tag" && { err "Inbound $tag already exists."; return 1; }
    [ -s "$XRAY_INB" ] || echo '[]' > "$XRAY_INB"

    case "$type" in
        reality)
            local sni="${extra:-www.microsoft.com}"
            xray_gen_reality_keys || { err "Failed to generate Reality keys."; return 1; }
            json="$(jq -n --arg tag "$tag" --argjson port "$port" --arg sni "$sni" \
                --arg priv "$R_PRIV" --arg pub "$R_PUB" --arg sid "$(rand_hex 8)" \
                '{tag:$tag,type:"reality",port:$port,sni:$sni,privateKey:$priv,publicKey:$pub,shortId:$sid}')" ;;
        vless-ws|vmess-ws)
            local path="${extra:-/$(rand_str 8)}" tls=false insecure=false
            [[ "$path" == /* ]] || path="/$path"
            if [ -n "$domain" ]; then
                tls=true
                ssl_have_le "$domain" || { warn "No Let's Encrypt cert for $domain - using self-signed (clients need allowInsecure)."; insecure=true; }
                paths="$(ssl_paths "$domain")"; cert="${paths% *}"; key="${paths#* }"
            fi
            json="$(jq -n --arg tag "$tag" --arg type "$type" --argjson port "$port" --arg host "$domain" \
                --arg path "$path" --argjson tls "$tls" --argjson insecure "$insecure" \
                --arg cert "${cert:-}" --arg key "${key:-}" \
                '{tag:$tag,type:$type,port:$port,host:$host,path:$path,tls:$tls,insecure:$insecure,cert:$cert,key:$key}')" ;;
        trojan)
            local insecure=false
            ssl_have_le "$domain" || { warn "No Let's Encrypt cert for '${domain:-<none>}' - using self-signed (clients need allowInsecure)."; insecure=true; }
            paths="$(ssl_paths "$domain")"; cert="${paths% *}"; key="${paths#* }"
            json="$(jq -n --arg tag "$tag" --argjson port "$port" --arg host "$domain" --argjson insecure "$insecure" \
                --arg cert "$cert" --arg key "$key" \
                '{tag:$tag,type:"trojan",port:$port,host:$host,tls:true,insecure:$insecure,cert:$cert,key:$key}')" ;;
        ss2022)
            json="$(jq -n --arg tag "$tag" --argjson port "$port" --arg k "$(openssl rand -base64 16)" \
                '{tag:$tag,type:"ss2022",port:$port,serverKey:$k}')" ;;
        *) err "Unknown inbound type: $type"; return 1 ;;
    esac

    inb_add "$json" || return 1
    case "$type" in ss2022) fw_allow "$port" both ;; *) fw_allow "$port" tcp ;; esac
    log_action "xray inbound added: $tag"
    xray_apply && ok "Protocol '$tag' enabled"
}

xray_del_inbound() {
    xray_inbound_exists "$1" || { err "Inbound '$1' not found."; return 1; }
    local port; port="$(jq -r --arg t "$1" '.[]|select(.tag==$t)|.port' "$XRAY_INB")"
    jq --arg t "$1" 'map(select(.tag!=$t))' "$XRAY_INB" | json_write "$XRAY_INB" || return 1
    fw_deny "$port" both
    log_action "xray inbound removed: $1"
    xray_apply
}

xray_list_inbounds() {
    if [ ! -s "$XRAY_INB" ] || [ "$(jq length "$XRAY_INB")" -eq 0 ]; then echo "No protocols configured."; return; fi
    printf "${BOLD}%-18s %-10s %-8s %s${NC}\n" "TAG" "TYPE" "PORT" "DETAILS"
    jq -r '.[] | [.tag,.type,(.port|tostring),
        (if .type=="reality" then "sni=\(.sni)"
         elif .type=="trojan" then (if .host=="" then "self-signed" else .host end)
         elif .type=="ss2022" then "2022-blake3-aes-128-gcm"
         else "path=\(.path) " + (if .tls then "tls(\(.host))" else "plain" end) end)] | @tsv' "$XRAY_INB" |
    while IFS=$'\t' read -r a b c d; do printf "%-18s %-10s %-8s %s\n" "$a" "$b" "$c" "$d"; done
}

#---- client links ---------------------------------------------------------------

# xray_user_links NAME -> prints one link per enabled protocol
xray_user_links() {
    local name="$1" u uuid pw ss ip ib type port host path rem addr
    [ -s "$XRAY_INB" ] || return 0
    u="$(jq -c --arg n "$name" '.[]|select(.name==$n)' "$USERS_DB")"
    [ -n "$u" ] || { err "User '$name' not found."; return 1; }
    uuid="$(jq -r .uuid <<<"$u")"; pw="$(jq -r .password <<<"$u")"; ss="$(jq -r .ss_key <<<"$u")"
    ip="$(get_public_ip)"
    while IFS= read -r ib; do
        [ -n "$ib" ] || continue
        type="$(jq -r .type <<<"$ib")"; port="$(jq -r .port <<<"$ib")"
        host="$(jq -r '.host // ""' <<<"$ib")"; path="$(jq -r '.path // ""' <<<"$ib")"
        local tls insecure ins=""
        tls="$(jq -r '.tls // false' <<<"$ib")"; insecure="$(jq -r '.insecure // false' <<<"$ib")"
        [ "$insecure" = true ] && ins="&allowInsecure=1"
        rem="$(urlenc "${name}-${type}")"
        addr="${host:-$ip}"
        case "$type" in
            reality)
                echo "vless://${uuid}@${ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$(jq -r .sni <<<"$ib")&fp=chrome&pbk=$(jq -r .publicKey <<<"$ib")&sid=$(jq -r .shortId <<<"$ib")&type=tcp#${rem}" ;;
            vless-ws)
                if [ "$tls" = true ]; then
                    echo "vless://${uuid}@${addr}:${port}?encryption=none&security=tls&sni=${host}&fp=chrome&type=ws&host=${host}&path=$(urlenc "$path")${ins}#${rem}"
                else
                    echo "vless://${uuid}@${ip}:${port}?encryption=none&security=none&type=ws${host:+&host=$host}&path=$(urlenc "$path")#${rem}"
                fi ;;
            vmess-ws)
                local vm
                vm="$(jq -cn --arg ps "${name}-${type}" --arg add "$addr" --arg port "$port" --arg id "$uuid" \
                    --arg host "$host" --arg path "$path" --arg tls "$([ "$tls" = true ] && echo tls)" \
                    '{v:"2",ps:$ps,add:$add,port:$port,id:$id,aid:"0",scy:"auto",net:"ws",type:"none",host:$host,path:$path,tls:$tls,sni:$host,fp:"chrome"}')"
                echo "vmess://$(b64 "$vm")" ;;
            trojan)
                echo "trojan://$(urlenc "$pw")@${addr}:${port}?security=tls&sni=${host:-www.bing.com}&type=tcp${ins}#${rem}" ;;
            ss2022)
                echo "ss://2022-blake3-aes-128-gcm:$(urlenc "$(jq -r .serverKey <<<"$ib"):${ss}")@${ip}:${port}#${rem}" ;;
        esac
    done < <(jq -c '.[]' "$XRAY_INB")
}

#---- usage ------------------------------------------------------------------------

xray_usage() { # prints "name up down" lines (bytes)
    xray_installed && svc_active xray || return 0
    "$XRAY_BIN" api statsquery --server="127.0.0.1:${XRAY_API_PORT}" -pattern "user>>>" 2>/dev/null |
    jq -r '[.stat[]? | (.name|split(">>>")) as $p | {u:$p[1], d:$p[3], v:((.value // 0)|tonumber)}]
           | group_by(.u)[] | [.[0].u,
               (map(select(.d=="uplink")|.v)|add // 0),
               (map(select(.d=="downlink")|.v)|add // 0)] | @tsv'
}

xray_show_usage() {
    local out
    out="$(xray_usage)"
    [ -n "$out" ] || { echo "No traffic recorded yet."; return; }
    printf "${BOLD}%-20s %-14s %-14s${NC}\n" "USER" "UPLOAD" "DOWNLOAD"
    while IFS=$'\t' read -r n up down; do
        printf "%-20s %-14s %-14s\n" "$n" "$(human_bytes "$up")" "$(human_bytes "$down")"
    done <<<"$out"
}

#---- menu ---------------------------------------------------------------------------

xray_add_inbound_wizard() {
    menu_header "➕ Add Xray protocol"
    echo "  1) VLESS + Reality + Vision   (recommended, no domain needed)"
    echo "  2) VLESS + WebSocket          (CDN friendly, TLS optional)"
    echo "  3) VMess + WebSocket          (legacy clients, TLS optional)"
    echo "  4) Trojan + TLS"
    echo "  5) Shadowsocks 2022"
    echo "  0) Back"
    echo -e "$LINE"
    local c port domain extra
    c="$(ask "Choose" "")"
    case "$c" in
        1) port="$(ask_port "Reality" 443)" || return
           extra="$(ask "Camouflage SNI (a real TLS 1.3 site)" "www.microsoft.com")"
           xray_add_inbound reality "$port" "" "$extra" ;;
        2|3) port="$(ask_port "WebSocket" 8443)" || return
           domain="$(ask "Domain for TLS (leave empty for plain WS)" "$(setting_get domain)")"
           if [ -n "$domain" ] && ! ssl_have_le "$domain"; then
               confirm "Issue a Let's Encrypt certificate for $domain now?" y && ssl_issue "$domain"
           fi
           extra="$(ask "WebSocket path" "/$(rand_str 8)")"
           xray_add_inbound "$([ "$c" = 2 ] && echo vless-ws || echo vmess-ws)" "$port" "$domain" "$extra" ;;
        4) port="$(ask_port "Trojan" 2053)" || return
           domain="$(ask "Domain (leave empty for self-signed)" "$(setting_get domain)")"
           if [ -n "$domain" ] && ! ssl_have_le "$domain"; then
               confirm "Issue a Let's Encrypt certificate for $domain now?" y && ssl_issue "$domain"
           fi
           xray_add_inbound trojan "$port" "$domain" ;;
        5) port="$(ask_port "Shadowsocks" 8388)" || return
           xray_add_inbound ss2022 "$port" ;;
    esac
}

xray_menu() {
    while true; do
        menu_header "🚀 Xray-core  (VLESS / VMess / Trojan / Shadowsocks)   [$(svc_state xray)]"
        echo "  1) Install / reinstall Xray"
        echo "  2) Update Xray-core"
        echo "  3) Add protocol"
        echo "  4) Remove protocol"
        echo "  5) List protocols"
        echo "  6) Traffic usage per user"
        echo "  7) Restart / apply config"
        echo "  8) View logs"
        echo "  9) Uninstall Xray"
        echo "  0) Back"
        echo -e "$LINE"
        case "$(ask "Choose" "")" in
            1) xray_install && xray_apply; pause ;;
            2) xray_update; pause ;;
            3) xray_require && xray_add_inbound_wizard; pause ;;
            4) xray_list_inbounds; xray_require && xray_del_inbound "$(ask "Tag to remove" "")"; pause ;;
            5) xray_list_inbounds; pause ;;
            6) xray_show_usage; pause ;;
            7) xray_apply; pause ;;
            8) journalctl -u xray -n 60 --no-pager; pause ;;
            9) confirm "Remove Xray completely?" n && xray_uninstall; pause ;;
            0|"") return ;;
        esac
    done
}
