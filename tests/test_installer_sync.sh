#!/usr/bin/env bash
# Runs the real git-sync block of install.sh against local repos, including the case that broke a
# real server: an existing single-branch clone made with `--branch feature`, then re-installing main.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }
G() { git -c user.name=t -c user.email=t@t "$@"; }

# the block between the markers in install.sh, with its helpers
BLOCK="$(sed -n '/^# >>> git-sync/,/^# <<< git-sync/p' "$ROOT/install.sh")"
[ -n "$BLOCK" ] || { echo "FAIL - git-sync markers not found in install.sh"; exit 1; }
sync_run() { # sync_run BRANCH
    ( BRANCH="$1"; HOME_DIR="$TMP/install"; REPO=x/y; GIT_URL="file://$TMP/origin.git"
      fail() { echo "INSTALLER-FAIL: $*" >&2; exit 1; }
      eval "$BLOCK" ) 2>"$TMP/err"
}

G init -q --bare "$TMP/origin.git" -b main
G clone -q "$TMP/origin.git" "$TMP/work" 2>/dev/null
( cd "$TMP/work" && echo v1 > f && G add -A && G commit -qm v1 && G push -q origin HEAD:main 2>/dev/null \
  && G checkout -qb feature && echo v2 > f && G add -A && G commit -qm v2 && G push -q origin feature 2>/dev/null )

# 1) fresh install of main
sync_run main
check "fresh install clones main"                         '[ "$(cat "$TMP/install/f")" = v1 ]'

# 2) THE BUG: server was installed with --branch feature (single-branch clone), now installs main
rm -rf "$TMP/install"; G clone -q --depth 1 -b feature "file://$TMP/origin.git" "$TMP/install" 2>/dev/null
check "precondition: single-branch clone of feature"      '[ "$(cat "$TMP/install/f")" = v2 ]'
sync_run main; rc=$?
check "installing main over a feature clone works (rc=0)"  '[ $rc -eq 0 ]'
check "…and now has main's code"                           '[ "$(cat "$TMP/install/f")" = v1 ] && [ "$(git -C "$TMP/install" rev-parse --abbrev-ref HEAD)" = main ]'

# 3) re-running on the same branch picks up new commits
( cd "$TMP/work" && G checkout -q main && echo v3 > f && G add -A && G commit -qm v3 && G push -q origin main 2>/dev/null )
sync_run main; rc=$?
check "re-running updates to the newest commit"            '[ $rc -eq 0 ] && [ "$(cat "$TMP/install/f")" = v3 ]'

# 4) switching back to the feature branch also works
sync_run feature; rc=$?
check "switching to another branch works"                  '[ $rc -eq 0 ] && [ "$(cat "$TMP/install/f")" = v2 ]'

# 5) unreachable remote aborts loudly
git -C "$TMP/install" remote set-url origin "file://$TMP/nope.git"
sync_run main; rc=$?
check "unreachable remote → non-zero and a clear message"  '[ $rc -ne 0 ] && grep -q "INSTALLER-FAIL" "$TMP/err"'

[ $fail = 0 ] && echo "ALL INSTALLER-SYNC TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
