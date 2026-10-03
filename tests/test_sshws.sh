#!/usr/bin/env bash
# SSH over WebSocket: the real proxy (ssh-ws/sshws.py) against a fake sshd with the user's exact payload,
# plus the Xray default-fallback generation. Offline (loopback only).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; PIDS=""
trap 'for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"' EXIT
export VPSM_ETC="$TMP/etc" VPSM_LOG_DIR="$TMP/log" VPSM_BACKUP_DIR="$TMP/bak" VPSM_NONINTERACTIVE=1
for f in common users ssl xray; do . "$ROOT/lib/$f.sh"; done
db_init; setting_set public_ip 203.0.113.7
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

# fake sshd: sends a banner, then echoes lines
cat > "$TMP/fakessh.py" <<'PY'
import socketserver, sys
class H(socketserver.StreamRequestHandler):
    def handle(self):
        self.wfile.write(b"SSH-2.0-FakeSSH\r\n")
        for line in self.rfile:
            self.wfile.write(b"echo:" + line)
socketserver.ThreadingTCPServer.allow_reuse_address = True
socketserver.ThreadingTCPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
SSHP=$((20000 + RANDOM % 10000)); WSP=$((SSHP + 1))
python3 "$TMP/fakessh.py" "$SSHP" & PIDS="$PIDS $!"
python3 "$ROOT/ssh-ws/sshws.py" --listen "127.0.0.1:$WSP" --ssh "127.0.0.1:$SSHP" & PIDS="$PIDS $!"
for _ in $(seq 50); do (exec 3<>/dev/tcp/127.0.0.1/$WSP) 2>/dev/null && break; read -rt 0.1 _ <> <(:) ; done

talk() { # talk 'request' 'after-data'  -> raw answer
    python3 - "$WSP" "$1" "${2:-}" <<'PY'
import socket, sys, time
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=5)
s.sendall(sys.argv[2].encode().decode("unicode_escape").encode("latin-1"))
time.sleep(0.5)
if sys.argv[3]:
    s.sendall(sys.argv[3].encode().decode("unicode_escape").encode("latin-1")); time.sleep(0.5)
s.settimeout(1); out = b""
try:
    while True:
        d = s.recv(4096)
        if not d: break
        out += d
except Exception: pass
sys.stdout.write(out.decode("latin-1"))
PY
}
PAYLOAD='GET / HTTP/1.1\r\nHost: ssl.andam.uk\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nUser-Agent: Mozilla/5.0 (Linux; Android 16)\r\nOrigin: https://ssl.andam.uk\r\n\r\n'
out="$(talk "$PAYLOAD" 'hello\r\n')"
check "answers 101 Switching Protocols"            'grep -q "^HTTP/1.1 101 Switching Protocols" <<<"$out"'
check "101 carries Upgrade: websocket"             'grep -qi "^Upgrade: websocket" <<<"$out"'
check "SSH banner follows the 101"                 'grep -q "SSH-2.0-FakeSSH" <<<"$out"'
check "data after the handshake reaches sshd"      'grep -q "echo:hello" <<<"$out"'
out="$(talk 'GET /anything HTTP/1.1\r\nHost: other.example\r\nUpgrade: websocket\r\n\r\n')"
check "any Host / path is accepted"                'grep -q "101 Switching" <<<"$out" && grep -q SSH-2.0 <<<"$out"'
out="$(talk 'GET / HTTP/1.1\r\nHost: x\r\nupgrade: WebSocket\r\n\r\nSSH-2.0-client\r\n')"
check "header case does not matter, early data kept" 'grep -q "101 Switching" <<<"$out" && grep -q "echo:SSH-2.0-client" <<<"$out"'
out="$(talk 'GET / HTTP/1.1\r\nHost: x\r\n\r\n')"
check "plain browser request → harmless 200 page, no SSH" 'grep -q "^HTTP/1.1 200 OK" <<<"$out" && ! grep -q SSH-2.0 <<<"$out"'
out="$(talk 'CONNECT 127.0.0.1:22 HTTP/1.1\r\nHost: x\r\n\r\n')"
check "CONNECT → 200 Connection established + tunnel" 'grep -q "200 Connection established" <<<"$out" && grep -q SSH-2.0 <<<"$out"'
out="$(talk 'garbage')"
check "garbage without header end is dropped quietly" '[ -z "$out" ]'

# --- Xray: SSH-WS becomes the DEFAULT fallback (no path) of BOTH the 443 TLS and 80 plain inbounds
echo '[]' > "$XRAY_INB"; XRAY_BIN=/bin/true
inb_add '{"tag":"multi-ws-443","type":"multi-ws","port":443,"plain_port":80,"host":"ssl.andam.uk","tls":true,"insecure":true,"cert":"c","key":"k","pVless":"/vless","pVmess":"/vmess","pTrojan":"/trojan","pSs":"/ss","lVless":10801,"lVmess":10802,"lTrojan":10803,"lSs":10804}'
user_add alice 0 >/dev/null
cfg="$(xray_build_config)"
check "without SSH-WS: only the 4 path fallbacks"   '[ "$(jq "[.inbounds[]|select(.port==80)|.settings.fallbacks[]]|length" <<<"$cfg")" = 4 ]'
setting_set sshws_port 10810
cfg="$(xray_build_config)"
check "port 80 gets a default fallback to SSH-WS"   '[ "$(jq -r "[.inbounds[]|select(.port==80)|.settings.fallbacks[]|select(.path==null)|.dest]|first" <<<"$cfg")" = "127.0.0.1:10810" ]'
check "port 443 gets the same default fallback"     '[ "$(jq -r "[.inbounds[]|select(.port==443)|.settings.fallbacks[]|select(.path==null)|.dest]|first" <<<"$cfg")" = "127.0.0.1:10810" ]'
check "default fallback is last (paths still win)"  '[ "$(jq -r ".inbounds[]|select(.port==80)|.settings.fallbacks[-1].path // \"none\"" <<<"$cfg")" = none ]'
check "the 4 proxy paths are unchanged"             '[ "$(jq -r "[.inbounds[]|select(.port==80)|.settings.fallbacks[].path|select(.!=null)]|join(\",\")" <<<"$cfg")" = "/vless,/vmess,/trojan,/ss" ]'
setting_del sshws_port
check "removing the setting removes the fallback"   '[ "$(xray_build_config | jq "[.inbounds[]|select(.port==80)|.settings.fallbacks[]]|length")" = 4 ]'

exit $fail
