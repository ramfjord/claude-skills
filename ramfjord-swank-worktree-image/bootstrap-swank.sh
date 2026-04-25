#!/usr/bin/env bash
# bootstrap-swank.sh — set up a per-worktree swank image under tmux.
#
#   usage: bootstrap-swank.sh [WORKTREE_PATH]   (default: $PWD)
#
# Picks a free port, derives the ASDF system name from the worktree's
# *.asd file, allocates a tmux session named after the worktree, runs
# run-swank.expect inside it, and writes .swank-port + .mcp.json on
# success. Refuses to clobber an existing tmux session.
#
# Tmux is the supervisor here; the bootstrap logic itself (which forms
# to send, when SBCL is ready for the next one) lives in the expect
# script. Swap this wrapper for systemd/whatever later without
# touching the bootstrap.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

worktree="${1:-$PWD}"
worktree="$(cd "$worktree" && pwd)"
session="$(basename "$worktree")"

asd="$(find "$worktree" -maxdepth 1 -name '*.asd' | head -n 1)"
if [[ -z "$asd" ]]; then
  echo "no .asd file in $worktree; cannot derive system name" >&2
  exit 1
fi
system="$(basename "$asd" .asd)"

if tmux has-session -t "$session" 2>/dev/null; then
  echo "tmux session '$session' already exists; refusing to bootstrap" >&2
  exit 1
fi

port=4005
while ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":${port}\$"; do
  port=$((port + 1))
done

echo "bootstrapping: session=$session system=$system port=$port path=$worktree"

tmux new-session -d -s "$session" -x 220 -y 50 \
  "$SCRIPT_DIR/run-swank.expect '$worktree' '$system' '$port'"

# tmux returns immediately; expect is still running inside the pane.
# Wait for the actual state we care about — the port being LISTEN —
# rather than for the expect script to "be done" (it never is; it
# `interact`s forever to keep sbcl alive).
deadline=$((SECONDS + 240))
while (( SECONDS < deadline )); do
  if ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":${port}\$"; then
    break
  fi
  if ! tmux has-session -t "$session" 2>/dev/null; then
    echo "ERROR: tmux session '$session' died during bootstrap" >&2
    exit 2
  fi
  sleep 0.2
done

if ! ss -tln | awk '{print $4}' | grep -q ":${port}\$"; then
  echo "ERROR: swank not listening on $port after 240s" >&2
  echo "  attach: tmux attach -t $session" >&2
  exit 2
fi

echo "$port" > "$worktree/.swank-port"
cat > "$worktree/.mcp.json" <<EOF
{
  "mcpServers": {
    "lisp": {
      "type": "stdio",
      "command": "/home/tramfjord/projects/lisp-mcp/lisp-mcp.sh",
      "args": [],
      "env": {
        "SWANK_PORT": "$port"
      }
    }
  }
}
EOF

echo "done. port=$port session=$session"
echo "restart Claude in $worktree (or /mcp) to pick up eval_swank"
