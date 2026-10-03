#!/usr/bin/env bash
#==============================================================================
# SSL certificates: Let's Encrypt (certbot, standalone) + self-signed fallback
#==============================================================================

SELF_CERT_DIR="$CERT_DIR/selfsigned"

ssl_selfsigned() { # creates a self-signed cert once (valid 10 years)
    mkdir -p "$SELF_CERT_DIR"
    if [ ! -s "$SELF_CERT_DIR/fullchain.pem" ]; then
        openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -days 3650 -subj "/CN=www.bing.com" \
            -keyout "$SELF_CERT_DIR/privkey.pem" -out "$SELF_CERT_DIR/fullchain.pem" >/dev/null 2>&1
        chmod 600 "$SELF_CERT_DIR/privkey.pem"
    fi
}

# ssl_paths DOMAIN -> prints "fullchain key" (Let's Encrypt if present)
ssl_paths() {
    local d="$1"
    if [ -n "$d" ] && [ -s "/etc/letsencrypt/live/$d/fullchain.pem" ]; then
        echo "/etc/letsencrypt/live/$d/fullchain.pem /etc/letsencrypt/live/$d/privkey.pem"
    else
        ssl_selfsigned
        echo "$SELF_CERT_DIR/fullchain.pem $SELF_CERT_DIR/privkey.pem"
    fi
}

ssl_have_le() { [ -n "$1" ] && [ -s "/etc/letsencrypt/live/$1/fullchain.pem" ]; }

ssl_install_certbot() {
    command -v certbot >/dev/null 2>&1 && return 0
    info "Installing certbot..."
    pkg_install certbot || return 1
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/vpsm.sh <<'EOF'
#!/bin/sh
for s in xray hysteria-server; do systemctl is-active --quiet "$s" && systemctl restart "$s"; done
exit 0
EOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/vpsm.sh
}

# ssl_issue DOMAIN [EMAIL]
ssl_issue() {
    local domain="$1" email="${2:-}" pub dns
    [ -n "$domain" ] || { err "Domain required."; return 1; }
    ssl_install_certbot || return 1

    pub="$(get_public_ip)"
    dns="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1; exit}')"
    if [ "$dns" != "$pub" ]; then
        warn "$domain resolves to '${dns:-nothing}' but this server is $pub."
        warn "Point the A record to $pub first (disable the Cloudflare proxy while issuing)."
        confirm "Try anyway?" n || return 1
    fi
    local hooks=()
    if port_in_use 80 tcp; then
        if ss -ltnp 2>/dev/null | awk '$4 ~ /:80$/' | grep -q '"xray"'; then
            info "Xray is using port 80 - it will be stopped briefly while the certificate is issued/renewed."
            hooks=(--pre-hook "systemctl stop xray" --post-hook "systemctl start xray")
        else
            warn "Port 80 is busy - certbot needs it for the HTTP-01 challenge."
            confirm "Continue anyway?" n || return 1
        fi
    fi
    fw_allow 80 tcp
    local args=(certonly --standalone -d "$domain" --agree-tos --non-interactive --keep-until-expiring "${hooks[@]}")
    if [ -n "$email" ]; then args+=(-m "$email"); else args+=(--register-unsafely-without-email); fi
    if certbot "${args[@]}"; then
        ok "Certificate issued for $domain"
        setting_set domain "$domain"
        log_action "ssl issued: $domain"
    else
        err "Certbot failed. Check DNS / port 80 and try again."; return 1
    fi
}

ssl_list() { command -v certbot >/dev/null 2>&1 && certbot certificates 2>/dev/null || echo "certbot is not installed."; }

ssl_renew() { certbot renew --quiet && ok "Renewal check finished" || err "Renewal failed"; }

ssl_menu() {
    while true; do
        menu_header "🔐 SSL Certificates"
        echo "  1) Issue Let's Encrypt certificate"
        echo "  2) List certificates"
        echo "  3) Force renewal test (dry-run)"
        echo "  4) Delete a certificate"
        echo "  0) Back"
        echo -e "$LINE"
        case "$(ask "Choose" "")" in
            1) ssl_issue "$(ask "Domain" "")" "$(ask "Email (optional)" "")"; pause ;;
            2) ssl_list; pause ;;
            3) certbot renew --dry-run; pause ;;
            4) local d; d="$(ask "Domain to delete" "")"
               [ -n "$d" ] && certbot delete --cert-name "$d" --non-interactive; pause ;;
            0|"") return ;;
        esac
    done
}
