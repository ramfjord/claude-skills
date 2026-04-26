#!/usr/bin/env bash
# assert-swank-healthy.sh DIR — bootstrap swank in DIR, assert it's healthy.
#
# Asserts post-bootstrap:
#   - .swank-session names a live tmux session, with <basename>-<hash> shape
#   - .swank-port and .mcp.json are written
#   - the recorded port is LISTEN and accepts a TCP connection
#
# Caller owns pre-cleanup of stale state and post-test teardown.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 1 ]]; then
  echo "usage: assert-swank-healthy.sh DIR" >&2
  exit 64
fi

dir="$(realpath "$1")"

fail() { echo "FAIL [$dir]: $*" >&2; exit 1; }

"$SCRIPT_DIR/bootstrap-swank.sh" "$dir"

[[ -f "$dir/.swank-session" ]] || fail ".swank-session not written"
session="$(cat "$dir/.swank-session")"
tmux has-session -t "$session" 2>/dev/null || fail "no tmux session '$session'"
[[ "$session" == "$(basename "$dir")-"* ]] \
  || fail "session name '$session' missing basename-hash format"
[[ -f "$dir/.swank-port" ]] || fail ".swank-port not written"
[[ -f "$dir/.mcp.json"  ]] || fail ".mcp.json not written"

port="$(cat "$dir/.swank-port")"
ss -tln | awk '{print $4}' | grep -q ":${port}\$" || fail "port $port not LISTEN"
timeout 2 bash -c "</dev/tcp/127.0.0.1/$port" || fail "cannot connect to 127.0.0.1:$port"

echo "OK [$dir]: session=$session port=$port"
