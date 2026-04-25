#!/usr/bin/env bash
# test.sh — exercise bootstrap-swank.sh against fixtures/elp.
#
# Asserts:
#   - tmux session 'elp' exists after bootstrap
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

SESSION="$(basename "$FIXTURE")"

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -f "$FIXTURE/.swank-port" "$FIXTURE/.mcp.json"
}
trap cleanup EXIT
cleanup  # drop any leftover state from a prior run

"$SCRIPT_DIR/bootstrap-swank.sh" "$FIXTURE"

fail() { echo "FAIL: $*" >&2; exit 1; }

tmux has-session -t "$SESSION" 2>/dev/null || fail "no tmux session '$SESSION'"
[[ -f "$FIXTURE/.swank-port" ]] || fail ".swank-port not written"
[[ -f "$FIXTURE/.mcp.json"  ]] || fail ".mcp.json not written"

PORT="$(cat "$FIXTURE/.swank-port")"
ss -tln | awk '{print $4}' | grep -q ":${PORT}\$" || fail "port $PORT not LISTEN"
timeout 2 bash -c "</dev/tcp/127.0.0.1/$PORT" || fail "cannot connect to 127.0.0.1:$PORT"

echo "PASS: bootstrap-swank.sh works against $FIXTURE on port $PORT"
