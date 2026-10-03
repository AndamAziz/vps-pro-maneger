#!/usr/bin/env bash
# Self-update against real (local) git repos: follows the installed branch, falls back to main when
# that branch was merged and deleted, runs `post-update` from the NEW code, and fails loudly offline.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export VPSM_ETC="$TMP/etc" VPSM_LOG_DIR="$TMP/log" VPSM_BACKUP_DIR="$TMP/bak" VPSM_NONINTERACTIVE=1
for f in common users ssl xray hysteria wireguard openvpn squid ssh system bot; do . "$ROOT/lib/$f.sh"; done
require_root() { :; }; svc_active() { return 1; }
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }
G() { git -c user.name=t -c user.email=t@t "$@"; }

# origin with main (v1) and a feature branch (v2)
G init -q --bare "$TMP/origin.git" -b main
G clone -q "$TMP/origin.git" "$TMP/work" 2>/dev/null
mk() { printf '#!/bin/sh\necho "post-update from %s" > "%s/marker"\n' "$1" "$TMP" > "$TMP/work/vpsmanager"; chmod +x "$TMP/work/vpsmanager"; }
( cd "$TMP/work" && mk v1 && G add -A && G commit -qm v1 && G push -q origin HEAD:main \
  && G checkout -qb feature && mk v2 && G add -A && G commit -qm v2 && G push -q origin feature 2>/dev/null )

# install like install.sh does: shallow single-branch clone of the feature branch
VPSM_HOME="$TMP/install"
G clone -q --depth 1 -b feature "file://$TMP/origin.git" "$VPSM_HOME" 2>/dev/null
check "installed from the feature branch"            '[ "$(git -C "$VPSM_HOME" rev-parse --abbrev-ref HEAD)" = feature ]'

# 1) normal update picks up a new commit on the same branch
( cd "$TMP/work" && mk v3 && G add -A && G commit -qm v3 && G push -q origin feature 2>/dev/null )
rm -f "$TMP/marker"; out="$(sys_self_update 2>&1)"; rc=$?
check "update follows the branch (rc=0)"             '[ $rc -eq 0 ] && grep -q "post-update from v3" "$TMP/marker"'
check "post-update runs the NEW code"                '[ -f "$TMP/marker" ]'

# 2) branch merged into main and deleted on GitHub
( cd "$TMP/work" && G checkout -q main && mk v4 && G add -A && G commit -qm v4 && G push -q origin main 2>/dev/null && G push -q origin --delete feature 2>/dev/null )
rm -f "$TMP/marker"; out="$(sys_self_update 2>&1)"; rc=$?
check "deleted branch → falls back to main (rc=0)"   '[ $rc -eq 0 ] && [ "$(git -C "$VPSM_HOME" rev-parse --abbrev-ref HEAD)" = main ]'
check "…and installs main's code"                    'grep -q "post-update from v4" "$TMP/marker"'
check "…and tells the user"                          'grep -q "switching to main" <<<"$out"'

# 3) later updates keep working on main
( cd "$TMP/work" && mk v5 && G add -A && G commit -qm v5 && G push -q origin main 2>/dev/null )
rm -f "$TMP/marker"; sys_self_update >/dev/null 2>&1; rc=$?
check "subsequent update on main works"              '[ $rc -eq 0 ] && grep -q "post-update from v5" "$TMP/marker"'

# 4) unreachable remote fails loudly and leaves the install intact
git -C "$VPSM_HOME" remote set-url origin "file://$TMP/does-not-exist.git"
out="$(sys_self_update 2>&1)"; rc=$?
check "unreachable GitHub → non-zero + error"        '[ $rc -ne 0 ] && grep -q "git update failed" <<<"$out"'
check "install untouched after a failed update"      '[ -x "$VPSM_HOME/vpsmanager" ]'

[ $fail = 0 ] && echo "ALL UPDATE TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
