#!/usr/bin/env bash
# test.sh — exercise bootstrap-swank.sh against fixtures/elp.
#
# Asserts:
#   - .swank-session is written and names a live tmux session
#   - the session name has the form <basename>-<hash>
#   - .swank-port and .mcp.json are written
#   - the recorded port is LISTEN
#   - a TCP connection to that port succeeds
#
# Cleans up tmux session and dropped files on exit.
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

"$SCRIPT_DIR/bootstrap-swank.sh" "$FIXTURE"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$FIXTURE/.swank-session" ]] || fail ".swank-session not written"
SESSION="$(cat "$FIXTURE/.swank-session")"
tmux has-session -t "$SESSION" 2>/dev/null || fail "no tmux session '$SESSION'"
[[ "$SESSION" == "$(basename "$FIXTURE")-"* ]] \
  || fail "session name '$SESSION' missing basename-hash format"
[[ -f "$FIXTURE/.swank-port" ]] || fail ".swank-port not written"
[[ -f "$FIXTURE/.mcp.json"  ]] || fail ".mcp.json not written"

PORT="$(cat "$FIXTURE/.swank-port")"
ss -tln | awk '{print $4}' | grep -q ":${PORT}\$" || fail "port $PORT not LISTEN"
timeout 2 bash -c "</dev/tcp/127.0.0.1/$PORT" || fail "cannot connect to 127.0.0.1:$PORT"

echo "PASS: bootstrap-swank.sh works against $FIXTURE on port $PORT"
