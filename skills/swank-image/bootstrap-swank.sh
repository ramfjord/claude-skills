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
worktree="$(realpath "$worktree")"
session_hash="$(printf '%s' "$worktree" | sha256sum | head -c 8)"
session="$(basename "$worktree")-${session_hash}"

# Main system: the .asd at the worktree root. That's the system the
# bootstrap will load and the session will be named after.
main_asd="$(find "$worktree" -maxdepth 1 -name '*.asd' | head -n 1)"
if [[ -z "$main_asd" ]]; then
  echo "no .asd file at root of $worktree; cannot derive system name" >&2
  exit 1
fi
system="$(basename "$main_asd" .asd)"

# Vendored deps: every other *.asd in the worktree (e.g. an elp/ subdir
# with its own elp.asd). Each parent dir gets pushed onto
# asdf:*central-registry* so the main system's :depends-on can resolve
# them. Hidden dirs (.git, .cache, etc.) are skipped.
asd_dirs=()
declare -A seen_dirs
while IFS= read -r asd; do
  d="$(dirname "$asd")"
  if [[ -z "${seen_dirs[$d]:-}" ]]; then
    seen_dirs[$d]=1
    asd_dirs+=("$d")
  fi
done < <(find "$worktree" -name '*.asd' -not -path '*/.*/*' 2>/dev/null)

if tmux has-session -t "$session" 2>/dev/null; then
  echo "tmux session '$session' already exists; refusing to bootstrap" >&2
  exit 1
fi

port=4005
while ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":${port}\$"; do
  port=$((port + 1))
done

# Vlime support: if VLIME_LISP_DIR points at an installed vlime checkout
# (the dir containing load-vlime.lisp), allocate a second port for vlime's
# listener. vlime:main starts both swank and its own JSON server in the
# same image, so editor + claude can attach to the same image via
# different ports/protocols. Default to lazy.nvim's path; users without
# vlime can unset VLIME_LISP_DIR to skip.
if [[ -z "${VLIME_LISP_DIR-}" ]]; then
  VLIME_LISP_DIR="$HOME/.local/share/nvim/lazy/vlime/lisp"
fi
vlime_port=0
if [[ -f "$VLIME_LISP_DIR/load-vlime.lisp" ]]; then
  vlime_port=$((port + 1))
  while ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":${vlime_port}\$"; do
    vlime_port=$((vlime_port + 1))
  done
else
  VLIME_LISP_DIR=""
fi

if (( vlime_port > 0 )); then
  echo "bootstrapping: session=$session system=$system swank-port=$port vlime-port=$vlime_port path=$worktree"
else
  echo "bootstrapping: session=$session system=$system port=$port path=$worktree (vlime disabled)"
fi

# Pass every asd-containing dir as an extra arg for run-swank.expect to
# push onto asdf:*central-registry*. Quote each path to survive the
# shell expansion inside tmux's command-string.
extra_args=""
for d in "${asd_dirs[@]}"; do
  extra_args+=" $(printf "%q" "$d")"
done

tmux_envs=( -e "TOOLS_LISP=$SCRIPT_DIR/tools.lisp" )
if (( vlime_port > 0 )); then
  tmux_envs+=( -e "VLIME_LISP_DIR=$VLIME_LISP_DIR" -e "VLIME_PORT=$vlime_port" )
fi

tmux new-session -d -s "$session" -x 220 -y 50 \
  "${tmux_envs[@]}" \
  "$SCRIPT_DIR/run-swank.expect '$worktree' '$system' '$port'$extra_args"

# tmux returns immediately; expect is still running inside the pane.
# Wait for the actual state we care about — the port(s) being LISTEN —
# rather than for the expect script to "be done" (it never is; it
# `interact`s forever to keep sbcl alive). When vlime is enabled, the
# vlime listener comes up *after* swank, so waiting on it implies both.
wait_port=$port
(( vlime_port > 0 )) && wait_port=$vlime_port

deadline=$((SECONDS + 240))
while (( SECONDS < deadline )); do
  if ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":${wait_port}\$"; then
    break
  fi
  if ! tmux has-session -t "$session" 2>/dev/null; then
    echo "ERROR: tmux session '$session' died during bootstrap" >&2
    exit 2
  fi
  sleep 0.2
done

if ! ss -tln | awk '{print $4}' | grep -q ":${wait_port}\$"; then
  echo "ERROR: server not listening on $wait_port after 240s" >&2
  echo "  attach: tmux attach -t $session" >&2
  exit 2
fi

echo "$port" > "$worktree/.swank-port"
echo "$session" > "$worktree/.swank-session"
if (( vlime_port > 0 )); then
  echo "$vlime_port" > "$worktree/.vlime-port"
fi
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

if (( vlime_port > 0 )); then
  echo "done. swank-port=$port vlime-port=$vlime_port session=$session"
else
  echo "done. port=$port session=$session"
fi
echo "restart Claude in $worktree (or /mcp) to pick up eval_swank"
