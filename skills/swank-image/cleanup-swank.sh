#!/usr/bin/env bash
# cleanup-swank.sh DIR — tear down a per-directory swank image.
#
# Reads .swank-session, kills the tmux session, removes .swank-session,
# .swank-port, and .mcp.json. Idempotent: missing pieces are no-ops,
# never errors.
#
# Use when removing a worktree, retiring a directory, or recovering
# from a stuck image. The merge-worktree skill calls this during
# teardown.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: cleanup-swank.sh DIR" >&2
  exit 64
fi

dir="$(realpath "$1")"

if [[ ! -d "$dir" ]]; then
  echo "cleanup-swank: directory does not exist: $dir" >&2
  exit 1
fi

torn_down=()

if [[ -f "$dir/.swank-session" ]]; then
  session="$(cat "$dir/.swank-session")"
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux kill-session -t "$session"
    torn_down+=("tmux session $session")
  fi
  rm -f "$dir/.swank-session"
  torn_down+=(".swank-session")
fi

if [[ -f "$dir/.swank-port" ]]; then
  rm -f "$dir/.swank-port"
  torn_down+=(".swank-port")
fi

if [[ -f "$dir/.vlime-port" ]]; then
  rm -f "$dir/.vlime-port"
  torn_down+=(".vlime-port")
fi

if [[ -f "$dir/.mcp.json" ]]; then
  rm -f "$dir/.mcp.json"
  torn_down+=(".mcp.json")
fi

if (( ${#torn_down[@]} == 0 )); then
  echo "cleanup-swank: nothing to tear down in $dir"
else
  echo "cleanup-swank: removed ${torn_down[*]} in $dir"
fi
