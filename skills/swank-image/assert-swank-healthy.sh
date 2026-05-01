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

# tools.lisp loaded? Ask the live SBCL via the tmux pane. Cheaper than
# speaking swank protocol from shell — we just push a form to the REPL
# and grep the captured pane for the response.
marker="tools-check-$$"
scratch="$(mktemp --suffix=.lisp)"
cat > "$scratch" <<'LISP'
(* 6 7)
(defun clt-test-fn (x) (* 2 x))
(+ 1 2)
LISP
# Three checks in one round trip:
#   - eval-form-at on line 1 returns 42 (the arithmetic form)
#   - eval-form-at on line 3 returns 3 (another arithmetic form)
#   - reload-form for 'clt-test-fn rebinds it; (clt-test-fn 5) → 10
tmux send-keys -t "$session" \
  "(format t \"$marker:~A:~A:~A~%\" (claude-tools:eval-form-at \"$scratch\" 1) (claude-tools:eval-form-at \"$scratch\" 3) (progn (claude-tools:reload-form \"$scratch\" 'clt-test-fn) (clt-test-fn 5)))" Enter
# Poll the pane for the marker line; SBCL evaluates fast but tmux pty
# flushing isn't instantaneous.
deadline=$((SECONDS + 5))
pane=""
while (( SECONDS < deadline )); do
  pane="$(tmux capture-pane -t "$session" -p -S -80)"
  echo "$pane" | grep -q "$marker:" && break
  sleep 0.2
done
if ! echo "$pane" | grep -q "$marker:42:3:10"; then
  echo "--- pane tail ---" >&2
  echo "$pane" | tail -20 >&2
  echo "-----------------" >&2
  rm -f "$scratch"
  fail "tools.lisp helpers misbehaved (expected $marker:42:3:10 in pane)"
fi
rm -f "$scratch"

echo "OK [$dir]: session=$session port=$port tools=loaded"
