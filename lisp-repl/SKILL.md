---
name: lisp-repl
description: Drive a persistent SBCL REPL in tmux for iterative ELP development. Use when evaluating Lisp forms, hot-reloading edited source files, running FiveAM tests in-image, or debugging via the SBCL debugger. Much faster than `make test` because the image stays warm.
---

# lisp-repl

A persistent SBCL session in tmux, with `:elp` and `:elp/tests` pre-loaded. Use this instead of shelling out to `make test` or `sbcl --script` when iterating — the image stays warm so reload + test cycles are sub-second.

## Session bootstrap (run once per Claude session)

Check if the session already exists; only create it if missing:

```bash
tmux has-session -t elp-repl 2>/dev/null || {
  tmux new-session -d -s elp-repl -x 220 -y 50 'sbcl --noinform'
  # Wait for prompt, then bootstrap
  sleep 1
  tmux send-keys -t elp-repl '(progn (push (truename "/home/tramfjord/projects/elp/") asdf:*central-registry*) (ql:quickload :elp) (ql:quickload :elp/tests))' Enter
  sleep 3
}
```

After bootstrap, verify with `tmux capture-pane -t elp-repl -p -S -20` — you should see `:ELP/TESTS` loaded and a `*` prompt.

## Evaluating a form

Write the form to a temp file and `load` it. This avoids quoting hell with `send-keys` and survives multi-line forms:

```bash
cat > /tmp/elp-eval.lisp <<'EOF'
(in-package :elp)
;; your forms here
(tokenize "Hello <%= name %>")
EOF
tmux send-keys -t elp-repl '(load "/tmp/elp-eval.lisp")' Enter
sleep 0.3
tmux capture-pane -t elp-repl -p -S -40
```

For one-liners, `send-keys` directly is fine:

```bash
tmux send-keys -t elp-repl '(elp:render-string "Hi <%= name %>" (list :name "world"))' Enter
```

## Hot reload after editing source

After editing `elp.lisp` or `cli.lisp`:

```bash
tmux send-keys -t elp-repl '(asdf:load-system :elp :force t)' Enter
```

For a single file, `(load "/home/tramfjord/projects/elp/elp.lisp")` is faster.

## Running tests in-image

Far faster than `make test`:

```bash
tmux send-keys -t elp-repl '(asdf:test-system :elp)' Enter
sleep 1
tmux capture-pane -t elp-repl -p -S -80
```

To run a single FiveAM test or suite:

```bash
tmux send-keys -t elp-repl '(fiveam:run! (quote some-test-name))' Enter
```

Reload tests after editing `elp-test.lisp`:

```bash
tmux send-keys -t elp-repl '(asdf:load-system :elp/tests :force t)' Enter
```

## Reading output reliably

`capture-pane -p -S -N` grabs the last N lines of scrollback. After sending a form, sleep briefly (eval time + a hair), then capture. If output is truncated or you're unsure eval finished, look for the trailing `*` prompt — that's the SBCL toplevel. Its absence means eval is still running OR you've dropped into the debugger.

For longer-running evals, poll:

```bash
for i in 1 2 3 4 5; do
  sleep 1
  tail=$(tmux capture-pane -t elp-repl -p -S -3 | tail -1)
  case "$tail" in *'* '*|'*') break;; esac
done
tmux capture-pane -t elp-repl -p -S -60
```

## Debugger recovery

If a form signals an unhandled condition, SBCL drops into its debugger. The prompt becomes `0] ` (or `1] `, etc. — the number is the recursion depth). Further input is interpreted as debugger commands until you abort.

To detect: capture the last line; if it matches `[0-9]+] $`, you're in the debugger.

To escape — send `top` (NOT `:q` — that's a SLIME convention and just evaluates the symbol `:Q` in bare SBCL):

```bash
tmux send-keys -t elp-repl 'top' Enter
```

`abort` or the number of the ABORT restart (read from the output — numbering is dynamic) also work. For nested debuggers (`1]`, `2]`, etc.), send `top` once per level until you see `*`. As a last resort, kill and rebootstrap:

```bash
tmux kill-session -t elp-repl
# then re-run bootstrap above
```

**Always** check for the debugger prompt after evaluating something that might error. Otherwise, the next `send-keys` will be interpreted as a debugger command rather than a Lisp form.

## Inspecting state

The image preserves all defined symbols, so you can poke at internals:

```bash
tmux send-keys -t elp-repl '(describe (quote elp:render-string))' Enter
tmux send-keys -t elp-repl '(trace elp:tokenize)' Enter   # then call something
tmux send-keys -t elp-repl '(untrace)' Enter
```

## When NOT to use this skill

- One-shot script-style runs where image warmth doesn't matter — just use `sbcl --script` or `make test`.
- Anything that needs a fresh image (e.g. verifying a clean-build works). For those, kill the session first or shell out.
- CI-equivalent verification before committing — `make test` runs the same suite from a cold image and is the source of truth.

## Skill iteration notes

This skill is young; refine it as friction shows up. Likely additions:
- A wrapper script (`repl.sh eval '...'`) that handles sleep + capture + debugger detection in one shot.
- A "reload + test" combo command for the tightest dev loop.
- Per-test-suite shortcuts once we know which suites get exercised most.
