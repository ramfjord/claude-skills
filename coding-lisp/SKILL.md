---
name: coding-lisp
description: Use whenever editing, reading, or debugging Lisp-family code (Common Lisp, Scheme, Clojure, Emacs Lisp — any .lisp/.cl/.scm/.ss/.rkt/.clj/.cljs/.el file). Encodes REPL-driven development habits that distinguish good Lisp work from edit-run-print loops, and counters reflexes carried over from non-image-based languages.
---

# coding-lisp

Lisp is a *REPL-driven* language. The default mode of work is not "edit file → run → read output" but "load image once → eval forms incrementally → inspect live values → redefine in place."

## Eval mechanism — the contract

This skill assumes a way to evaluate forms in a live Lisp image is available. The typical mechanism is an MCP server tool such as `eval_swank` from `lisp-mcp`, which talks to a long-running SBCL with a swank server. Anything that satisfies "I can send a form and get back the value, side effects visible to subsequent forms" works — a per-worktree image (see a project's `swank-worktree-image` skill if one exists), a global dev image, or your own setup.

If no eval mechanism is available, surface that to the user before continuing — the rest of this skill assumes one exists.

The four habits below are ordered by how strongly they counter wrong reflexes. Every one of them counters a default I'd otherwise apply.

## 1. Inspect, don't guess

**Reflex to override:** read source files to predict what a function returns or what shape a value has.

**Do instead:** call the thing in the live image with a real input and look at the actual return value. Use `describe`, `inspect`, `type-of`, `class-of` to interrogate live objects.

```lisp
(describe #'tokenize)        ; signature, docstring, where defined
(type-of *some-result*)      ; what is this thing actually
(inspect *some-result*)      ; interactive walker (CL — limited via eval-only MCP)
```

For Clojure: `(class x)`, `(meta #'foo)`, `(source foo)`.
For Scheme: `,desc foo` in many REPLs, or `(procedure-arity ...)`.

This is the single biggest behavior change vs. how you'd work in Python/Go. The image *has the answer*; reading code to predict the answer is wasted effort and often wrong (especially with macros, generic functions, or runtime dispatch).

## 2. Errors carry information — read them, don't escape them

**Reflex to override:** treat an error as a wall and immediately go back to reading source.

**Do instead:** read the condition. The condition object carries the operator, the offending values, and often a hint at the right restart. Most eval-via-MCP tools auto-abort the debugger and return the condition as text — so you don't get to interactively pick restarts, but you still get the diagnostic information for free.

When the human collaborator has a real debugger attached (via Sly/SLIME/Vlime/nvlime to the same swank), they *do* get the interactive debugger and can:
- `backtrace 10` — see the call stack
- `(sb-debug:var 'foo)` / `(sb-debug:arg 0)` — inspect locals
- pick a restart by number, or `RETURN expr` to substitute a value
- edit the source, re-eval the `defun`, then `RESTART-FRAME` to retry

So when you encounter an error eval'ing via MCP and the right move involves picking a restart or inspecting frames, surface that to the user and let them drive from their editor — they have access to context you don't.

## 3. `trace` over print debugging

**Reflex to override:** add `(format t "~A~%" x)` calls to see what's happening, then forget to remove them, then add more.

**Do instead:** `trace` the function. Every call shows args + return value. `untrace` cleans up automatically.

```lisp
(trace tokenize)
(render-string "hello <%= name %>" '(:name "world"))
;; auto-prints: 0: (TOKENIZE "hello <%= name %>")
;;              0: TOKENIZE returned ((:TEXT "hello ") (:EXPR " name "))
(untrace tokenize)
;; or (untrace) to clear all traces
```

Works on multiple functions at once: `(trace tokenize parse render)`. For methods and macros there are options: `(trace foo :methods t)`. No source edits, no risk of committing print statements, no churn.

Trace output goes to `*trace-output*`. If your eval mechanism doesn't capture it (some MCP transports only return the form's value), wrap the call in `with-output-to-string` to grab it:

```lisp
(with-output-to-string (*trace-output*)
  (trace tokenize)
  (unwind-protect (render-string "..." '())
    (untrace)))
```

In Clojure: `clojure.tools.trace/trace-vars`. In Scheme: implementation-specific (`,trace` in Chez/Racket).

## 4. Redefine on the fly — the warm image is the point

**Reflex to override:** treat a code change as requiring a restart. Edit, kill, re-run, wait for setup, retry.

**Do instead:** edit the function, re-eval its `defun` (or `(load "file.lisp")` for a whole file), call again. The image keeps:
- All other definitions.
- All bound variables (`*sample-input*`, `*parsed-config*`, etc.).
- Open connections, loaded data, accumulated state.

```lisp
;; After editing a source file:
(load "/absolute/path/to/file.lisp")
;; Or, for whole-system reload:
(asdf:load-system :elp :force t)
```

This is *why* REPL-driven dev is fast: you pay setup cost once and iterate on top of it. If you find yourself restarting the image more than once a session, ask why — usually it's because something got into a wedged state, and the right fix is to make that state inspectable/resettable from a function call rather than to restart.

Two concrete moves that make this work:
- **Bind expensive setup to a global**: `(defparameter *sample* (parse-big-thing "..."))`. Now you can poke at `*sample*` for an hour without re-parsing.
- **Use `defparameter`, not `defvar`, while developing**: `defvar` won't overwrite an existing binding, so re-evaling it does nothing — surprising and frustrating during iteration. Switch to `defvar` only when the value should genuinely persist across reloads.

## Cross-cutting: when to fall back to file-based workflow

REPL-driven dev is the default. Fall back to cold runs (`make test`, `sbcl --script`) only for:
- Final pre-commit verification (the warm image may have stale definitions you forgot about).
- Reproducing a CI failure.
- Anything where image cleanliness is part of what you're testing (e.g. "does this load from scratch").

If you find yourself reaching for a cold run during normal iteration, that's a smell — the live-image workflow should be faster *and* give you more information.

## Code review is REPL work too

Reviewing Lisp without running it leaves the best tool on the table. Even in "read-only" review, the live image accelerates understanding:

- Call the function under review on a sample input — a real return value beats a predicted one.
- `(macroexpand-1 '(some-macro ...))` to see what a macro actually generates, instead of mentally simulating it.
- `(describe #'foo)` for signature, docstring, and where it's defined — faster than grep for "what is this."
- `(trace foo)` then exercise the surrounding code path to see *which* call sites hit it and with what args. Great for "is this function actually used the way the PR claims."
- For a refactor PR, eval both the old and new versions on the same inputs and diff the results.

The only review work that doesn't benefit is review *of code you can't load* (depends on something you don't have, or a different runtime). Otherwise: load the branch, warm an image, poke at it.

## When this skill doesn't apply

- Pure config edits to `.lisp` files that aren't code (rare but exists — some config languages use s-exprs).
- Editing this skill itself or other meta-files.
