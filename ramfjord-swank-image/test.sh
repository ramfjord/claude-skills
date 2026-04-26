#!/usr/bin/env bash
# test.sh — single-dir smoke test of bootstrap-swank.sh against fixtures/elp.
#
# Thin wrapper around assert-swank-healthy.sh. Cleans up before and after.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE="$REPO_ROOT/fixtures/elp"

if [[ ! -d "$FIXTURE" ]]; then
  echo "fixture missing: $FIXTURE" >&2
  echo "(per CLAUDE.md, clone https://github.com/ramfjord/elp there)" >&2
  exit 1
fi

cleanup() {
  if [[ -f "$FIXTURE/.swank-session" ]]; then
    local session
    session="$(cat "$FIXTURE/.swank-session")"
    tmux kill-session -t "$session" 2>/dev/null || true
  fi
  rm -f "$FIXTURE/.swank-port" "$FIXTURE/.swank-session" "$FIXTURE/.mcp.json"
}
trap cleanup EXIT
cleanup  # drop any leftover state from a prior run

"$SCRIPT_DIR/assert-swank-healthy.sh" "$FIXTURE"

# Recovery scenario: simulate a host reboot (or crashed tmux server) by
# killing the session while .swank-session lingers on disk. Bootstrap
# should come back up with the same session name. Pinning this so a
# future hash-scheme change can't silently break recovery.
session_before="$(cat "$FIXTURE/.swank-session")"
tmux kill-session -t "$session_before"
tmux has-session -t "$session_before" 2>/dev/null \
  && { echo "FAIL: tmux session '$session_before' still alive after kill" >&2; exit 1; }
[[ -f "$FIXTURE/.swank-session" ]] \
  || { echo "FAIL: .swank-session disappeared with the tmux session" >&2; exit 1; }

"$SCRIPT_DIR/assert-swank-healthy.sh" "$FIXTURE"

session_after="$(cat "$FIXTURE/.swank-session")"
[[ "$session_after" == "$session_before" ]] \
  || { echo "FAIL: session name changed across recovery: $session_before → $session_after" >&2; exit 1; }

echo "PASS: bootstrap-swank.sh works against $FIXTURE (incl. stale-session recovery)"
