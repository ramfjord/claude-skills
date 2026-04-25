---
name: swank-worktree-image
description: Set up and use a per-worktree Common Lisp image (SBCL + swank) wired to lisp-mcp's eval_swank, so each git worktree has its own isolated live image. Use when starting work in a new worktree, recovering an existing one, or troubleshooting why eval_swank isn't reaching the expected image.
---

# swank-worktree-image

Each git worktree gets its own SBCL image with a swank server, accessed via `lisp-mcp`'s `eval_swank` tool. Worktrees are isolated — different ports, different sessions, different state — so parallel features can't surprise each other. The user typically attaches their editor (nvlime/Vlime) to the same swank port for review; Claude attaches via lisp-mcp.

This skill is the *setup* side of the workflow. For *using* the eval mechanism once it exists, see `coding-lisp`.

## Conventions

- **One tmux session per worktree**, named after the worktree directory's basename. Example: worktree at `~/projects/elp-streams` → tmux session `elp-streams`.
- **Port stored in `.swank-port`** at the worktree root. Plain text, just the integer. Gitignored.
- **`.mcp.json`** at the worktree root, project-scoped, with `SWANK_PORT` set to match. Gitignored.
- **lisp-mcp lives at `~/projects/lisp-mcp`** with the entry script `lisp-mcp.sh`.
- **Port range**: start at 4005, increment per worktree. Skip ports already in use (any LISTEN socket).

## Quick checks before doing anything

When opening a worktree, first establish what exists:

```bash
# Is there a session for this worktree?
WORKTREE_NAME=$(basename "$PWD")
tmux has-session -t "$WORKTREE_NAME" 2>/dev/null && echo "session: yes" || echo "session: no"

# Is there a recorded port?
[ -f .swank-port ] && echo "port: $(cat .swank-port)" || echo "port: none"

# Is .mcp.json present?
[ -f .mcp.json ] && echo "mcp.json: yes" || echo "mcp.json: no"

# Does eval_swank work? Try a no-op.
# (skip if mcp.json missing — Claude won't have the tool yet)
```

Four states, four responses:

1. **All present, port listening, eval_swank works** → ready to use, no setup needed.
2. **Session present, port listening, but `.mcp.json` missing** → write `.mcp.json` and ask user to restart Claude (MCP is bound at session start).
3. **Session present, port not listening** → swank crashed or was never started. Re-bootstrap swank in the existing session.
4. **No session at all** → full bootstrap (below).

## Full bootstrap (state 4)

```bash
WORKTREE_NAME=$(basename "$PWD")
WORKTREE_PATH="$PWD"

# Pick the first free port starting at 4005
PORT=4005
while ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":$PORT$"; do
  PORT=$((PORT + 1))
done
echo "$PORT" > .swank-port

# Start tmux session with SBCL
tmux new-session -d -s "$WORKTREE_NAME" -x 220 -y 50 \
  "cd $WORKTREE_PATH && sbcl --noinform"
sleep 1

# Bootstrap the image: load the project, start swank
tmux send-keys -t "$WORKTREE_NAME" \
  "(progn (push (truename \"$WORKTREE_PATH/\") asdf:*central-registry*) (ql:quickload :swank) (asdf:load-system :elp) (swank:create-server :port $PORT :dont-close t))" Enter
sleep 3

# Verify swank is listening
ss -tln | grep -q ":$PORT" || echo "WARNING: swank did not start on $PORT"

# Write .mcp.json
cat > .mcp.json <<EOF
{
  "mcpServers": {
    "lisp": {
      "type": "stdio",
      "command": "/home/tramfjord/projects/lisp-mcp/lisp-mcp.sh",
      "args": [],
      "env": {
        "SWANK_PORT": "$PORT"
      }
    }
  }
}
EOF
```

After bootstrap, **the MCP tools are not yet available in the current Claude session** — MCP servers bind at Claude session start. Tell the user:

> Setup complete on port `$PORT`. Restart Claude in this directory (or run `/mcp`) to pick up `eval_swank`.

Then `coding-lisp` takes over for the actual work.

## Adapting the bootstrap to other projects

The recipe above hardcodes `(asdf:load-system :elp)`. For other projects:

- Replace `:elp` with the project's ASDF system name. If you don't know it, check the `.asd` file in the worktree root.
- If the project uses Quicklisp dependencies, `ql:quickload` works instead of `asdf:load-system`.
- If there's no ASDF system, `(load "main.lisp")` or whatever the project's entry-point file is.

The rest (port allocation, session naming, swank startup, `.mcp.json` template) is project-agnostic.

## Re-bootstrap swank in an existing session (state 3)

The image is alive but swank died (rare — usually means a thread error in user code took the listener down):

```bash
WORKTREE_NAME=$(basename "$PWD")
PORT=$(cat .swank-port)
tmux send-keys -t "$WORKTREE_NAME" \
  "(swank:create-server :port $PORT :dont-close t)" Enter
sleep 1
ss -tln | grep -q ":$PORT" || echo "WARNING: swank still not listening"
```

If the image itself is wedged (debugger, infinite loop), kill the session and full-bootstrap.

## Editor connection (for the human)

Once a session is up on port `N`, the user can attach from nvim with nvlime/Vlime:

```vim
:VlimeConnect 127.0.0.1 N
```

Same image as Claude's `eval_swank`. State changes from either side are visible to the other immediately.

## Teardown

When a worktree is being deleted:

```bash
WORKTREE_NAME=$(basename "$PWD")
tmux kill-session -t "$WORKTREE_NAME" 2>/dev/null
# .swank-port and .mcp.json go away with the worktree directory
```

Always confirm with the user before killing a session — they may have unsaved REPL state (rebuilding which costs them).

## Anti-patterns

- **Don't share images across worktrees.** The whole point of per-worktree images is isolation. If two worktrees both want port 4005, allocate the second one to 4006.
- **Don't try to persist images across reboots.** When the host reboots, all images go away cleanly. Restart sessions on demand. (`sb-ext:save-lisp-and-die` exists but using it routinely defeats the "code in files, image is workspace" mental model.)
- **Don't put project-specific eval logic in this skill.** This skill sets up the *mechanism*. What to do once the mechanism exists belongs in `coding-lisp` or project-specific guidance.
- **Don't commit `.mcp.json` or `.swank-port`.** Both are per-machine, per-worktree state. Add to `.gitignore` if they aren't already.

## Verification

After bootstrap (and Claude restart), confirm end-to-end:

```
mcp__lisp__eval_swank: (list :pid (sb-posix:getpid)
                             :loaded (and (find-package :elp) t))
```

Expected: a PID matching the `sbcl` process bound to your `.swank-port`, and `:LOADED T`.

If the PID doesn't match, lisp-mcp is talking to a different image than you expect — most often because two worktrees collided on a port, or because an old session is still holding 4005 from a prior worktree.
