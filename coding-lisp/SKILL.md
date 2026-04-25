---
name: lisp-development
description: Use whenever editing, reading, or debugging Lisp-family code (Common Lisp, Scheme, Clojure, Emacs Lisp — any .lisp/.cl/.scm/.ss/.rkt/.clj/.cljs/.el file). Encodes REPL-driven development habits that distinguish good Lisp work from edit-run-print loops, and counters reflexes carried over from non-image-based languages.
---

# lisp-development

Lisp is a *REPL-driven* language. The default mode of work is not "edit file → run → read output" but "load image once → eval forms incrementally → inspect live values → redefine in place." If a project ships a REPL-driver skill (e.g. `lisp-repl` in this repo), use it for the mechanics. If not, drive an SBCL/Scheme/Clojure REPL via tmux yourself — anything to keep an image warm.

The four habits below are ordered by how strongly they counter wrong reflexes. Every one of them counters a default I'd otherwise apply.

## 1. Inspect, don't guess

**Reflex to override:** read source files to predict what a function returns or what shape a value has.

**Do instead:** call the thing in the REPL with a real input and look at the actual return value. Use `describe`, `inspect`, `type-of`, `class-of` to interrogate live objects.

```lisp
(describe #'tokenize)        ; signature, docstring, where defined
(type-of *some-result*)      ; what is this thing actually
(inspect *some-result*)      ; interactive walker into nested structure (CL)
```

For Clojure: `(class x)`, `(meta #'foo)`, `(source foo)` (in REPL).
For Scheme: `,desc foo` in many REPLs, or `(procedure-arity ...)`.

This is the single biggest behavior change vs. how you'd work in Python/Go. The image *has the answer*; reading code to predict the answer is wasted effort and often wrong (especially with macros, generic functions, or runtime dispatch).

## 2. The debugger is a workspace, not an obstacle

**Reflex to override:** when a function errors and drops into the debugger, immediately escape (`top` in SBCL) and re-read the code to figure out what went wrong.

**Do instead:** stay in the debugger. You're stopped *at the live frame* with all locals intact. This is a gift, not a problem.

```
0] backtrace 10           ; see the call stack
0] (sb-debug:var 'foo)    ; inspect a local by name
0] (sb-debug:arg 0)       ; first arg of current frame
0] print                  ; show the failing call form
```

Most fix loops can happen entirely in the debugger:
1. Inspect the locals → see *exactly* which value is wrong.
2. Hypothesize a fix.
3. Edit the source file.
4. Re-eval the `defun` (in another window, or via `:eval` in some debuggers).
5. `RESTART-FRAME` to re-run the same frame with the new definition.

If the fix is to substitute a value rather than change code: `RETURN expr` returns `expr` from the failing frame and resumes execution. Or pick the `USE-VALUE` / `STORE-VALUE` restart if the condition offers it (it'll prompt `Enter a form to be evaluated:` — supply the value).

The reflex to escape immediately throws away all of this. Only `top` after you've extracted what you need.

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

In Clojure: `clojure.tools.trace/trace-vars`. In Scheme: implementation-specific (`,trace` in Chez/Racket).

## 4. Redefine on the fly — the warm image is the point

**Reflex to override:** treat a code change as requiring a restart. Edit, kill, re-run, wait for setup, retry.

**Do instead:** edit the function, re-eval its `defun` (or `(load "file.lisp")` for a whole file), call again. The image keeps:
- All other definitions.
- All bound variables (`*sample-input*`, `*parsed-config*`, etc.).
- Open connections, loaded data, accumulated state.

This is *why* REPL-driven dev is fast: you pay setup cost once and iterate on top of it. If you find yourself restarting the REPL more than once a session, ask why — usually it's because something got into a wedged state, and the right fix is to make that state inspectable/resettable from a function call rather than to restart.

Two concrete moves that make this work:
- **Bind expensive setup to a global**: `(defparameter *sample* (parse-big-thing "..."))`. Now you can poke at `*sample*` for an hour without re-parsing.
- **Use `defparameter`, not `defvar`, while developing**: `defvar` won't overwrite an existing binding, so re-evaling it does nothing — surprising and frustrating during iteration. Switch to `defvar` only when the value should genuinely persist across reloads.

## Cross-cutting: when to fall back to file-based workflow

REPL-driven dev is the default. Fall back to cold runs (`make test`, `sbcl --script`) only for:
- Final pre-commit verification (the warm image may have stale definitions you forgot about).
- Reproducing a CI failure.
- Anything where image cleanliness is part of what you're testing (e.g. "does this load from scratch").

If you find yourself reaching for a cold run during normal iteration, that's a smell — the REPL workflow should be faster *and* give you more information.

## Code review is REPL work too

Reviewing Lisp without running it leaves the best tool on the table. Even in "read-only" review, the REPL accelerates understanding:

- Call the function under review on a sample input — a real return value beats a predicted one.
- `(macroexpand-1 '(some-macro ...))` to see what a macro actually generates, instead of mentally simulating it.
- `(describe #'foo)` for signature, docstring, and where it's defined — faster than grep for "what is this."
- `(trace foo)` then exercise the surrounding code path to see *which* call sites hit it and with what args. Great for "is this function actually used the way the PR claims."
- For a refactor PR, eval both the old and new versions on the same inputs and diff the results.

The only review work that doesn't benefit is review *of code you can't load* (depends on something you don't have, or a different runtime). Otherwise: load the branch, warm an image, poke at it.

## When this skill doesn't apply

- Pure config edits to `.lisp` files that aren't code (rare but exists — some config languages use s-exprs).
- Editing this skill itself or other meta-files.
