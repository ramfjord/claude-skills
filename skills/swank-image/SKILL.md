---
name: swank-image
description: Set up and use a per-directory Common Lisp image (SBCL + swank) wired to lisp-mcp's eval_swank. Typically one image per worktree (so parallel tasks are isolated), but works in any directory with an `.asd` file — including the main checkout while drafting plans. Use when starting work in a new directory, recovering an existing image, or troubleshooting why eval_swank isn't reaching the expected one.
---

# ramfjord:swank-image

Each project directory gets its own SBCL image with a swank server, accessed via `lisp-mcp`'s `eval_swank` tool. Directories are isolated — different ports, different sessions, different state — so parallel work can't surprise itself. The common case is one image per git worktree (each task gets its own); the same mechanism also works in the main checkout for plan-time exploration. Swank runs unattended in a tmux session; Claude is the only client during iteration via lisp-mcp. The user attaches their editor (nvlime/Vlime) to the same port *after* iteration, for review — so don't assume a human is sitting at an interactive debugger while you're working.

This skill is the *setup* side of the workflow. For *using* the eval mechanism once it exists, see `ramfjord:coding-lisp`.

## Conventions

- **One tmux session per directory**, named `<basename>-<8-char hash of realpath>` so two directories with the same basename (e.g. two clones of `elp/`) can't collide. Example: worktree at `~/projects/elp-streams` → tmux session `elp-streams-a1b2c3d4`.
- **Session name stored in `.swank-session`** at the directory root. Always read this file rather than re-deriving from `pwd`, so the naming scheme can change later without orphaning live sessions. Gitignored.
- **Port stored in `.swank-port`** at the directory root. Plain text, just the integer. Gitignored.
- **`.mcp.json`** at the directory root, project-scoped, with `SWANK_PORT` set to match. Gitignored.
- **lisp-mcp lives at `~/projects/lisp-mcp`** with the entry script `lisp-mcp.sh`.
- **Port range**: start at 4005, increment per directory. Skip ports already in use (any LISTEN socket).

## Quick checks before doing anything

When opening a directory, first establish what exists:

```bash
# Is there a session for this directory?
if [ -f .swank-session ]; then
  SESSION_NAME=$(cat .swank-session)
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    && echo "session: $SESSION_NAME" \
    || echo "session: no (stale .swank-session)"
else
  echo "session: no"
fi

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

Do this automatically — don't ask the user first. By invoking this skill
they've already opted into the per-worktree image setup; the only cost
is one Claude restart at the end (which they'd have to do anyway).

Run the bootstrap script from this skill directory, passing the directory path:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/swank-image/bootstrap-swank.sh "$PWD"
```

The script:
- picks a free port starting at 4005
- derives the ASDF system name from the directory's `*.asd` file
- creates a tmux session named after the directory
- runs `run-swank.expect` inside it (drives SBCL through the load
  sequence, blocking on the prompt rather than sleeping)
- writes `.swank-port`, `.swank-session`, and `.mcp.json` once swank is actually LISTEN
- refuses if a tmux session of the same name already exists

The bootstrap forms are: push every directory containing a `*.asd`
file (the worktree itself + any vendored deps in subdirs) onto
`asdf:*central-registry*`, then `(ql:quickload :swank)`,
`(asdf:load-system :SYSTEM)`, `(swank:create-server :port PORT
:dont-close t)`. They are sent as **separate forms, not one `progn`**
— the reader processes a whole form before any evaluation, so a
`progn` containing `swank:create-server` fails because the SWANK
package doesn't exist at read time.

**Vendored ASDF deps are picked up automatically.** Any `*.asd` found
under the worktree (excluding hidden dirs like `.git`/`.cache`) gets
its parent directory pushed onto the central-registry, in addition to
the worktree root. So a project layout like

```
my-project/
  my-project.asd          ; depends-on ("elp" ...)
  elp/elp.asd             ; vendored
```

just works — `(asdf:load-system :my-project)` resolves `:elp` from
`elp/`. No per-project configuration needed.

After bootstrap, **the MCP tools are not yet available in the current Claude session** — MCP servers bind at Claude session start. Tell the user:

> Setup complete on port `$PORT`. Restart Claude in this directory (or run `/mcp`) to pick up `eval_swank`.

Then `ramfjord:coding-lisp` takes over for the actual work.

### Testing the bootstrap

`./test.sh` in this skill directory runs `bootstrap-swank.sh` against
`fixtures/elp/` and asserts the tmux session, files, listening port,
and TCP connectivity. Run it after editing `bootstrap-swank.sh` or
`run-swank.expect`.

## Re-bootstrap swank in an existing session (state 3)

The image is alive but swank died (rare — usually means a thread error in user code took the listener down):

```bash
SESSION_NAME=$(cat .swank-session)
PORT=$(cat .swank-port)
tmux send-keys -t "$SESSION_NAME" \
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

When a directory's image is no longer needed (worktree removal, retiring
a project, recovering from a wedged image), run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/swank-image/cleanup-swank.sh "$DIR"
```

The script reads `.swank-session`, kills the named tmux session if it's
alive, and removes `.swank-session`, `.swank-port`, and `.mcp.json`. It
is idempotent — missing pieces are no-ops, never errors. The
`ramfjord:merge-worktree` skill (when implemented) calls this during
worktree teardown.

Always confirm with the user before killing a session in an actively-used
directory — they may have unsaved REPL state worth preserving.

## Anti-patterns

- **Don't share images across directories.** The whole point of per-directory images is isolation: each worktree gets its own so parallel tasks can't surprise each other, and the main checkout's planning image doesn't bleed into task images. If two directories both want port 4005, allocate the second one to 4006.
- **Don't try to persist images across reboots.** When the host reboots, all images go away cleanly. Restart sessions on demand. (`sb-ext:save-lisp-and-die` exists but using it routinely defeats the "code in files, image is workspace" mental model.)
- **Don't put project-specific eval logic in this skill.** This skill sets up the *mechanism*. What to do once the mechanism exists belongs in `coding-lisp` or project-specific guidance.
- **Don't commit `.mcp.json`, `.swank-port`, or `.swank-session`.** All three are per-machine, per-worktree state. Add to `.gitignore` if they aren't already.

## Verification

After bootstrap (and Claude restart), confirm end-to-end:

```
mcp__lisp__eval_swank: (list :pid (sb-posix:getpid)
                             :loaded (and (find-package :elp) t))
```

Expected: a PID matching the `sbcl` process bound to your `.swank-port`, and `:LOADED T`.

If the PID doesn't match, lisp-mcp is talking to a different image than you expect — most often because two directories collided on a port, or because an old session is still holding 4005 from a prior directory.
