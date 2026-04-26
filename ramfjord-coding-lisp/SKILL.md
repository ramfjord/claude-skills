---
name: ramfjord-coding-lisp
description: Use whenever editing, reading, or debugging Lisp-family code (Common Lisp, Scheme, Clojure, Emacs Lisp — any .lisp/.cl/.scm/.ss/.rkt/.clj/.cljs/.el file). Encodes REPL-driven development habits that distinguish good Lisp work from edit-run-print loops, and counters reflexes carried over from non-image-based languages.
---

# ramfjord-coding-lisp

Lisp is a *REPL-driven* language. The default mode of work is not "edit file → run → read output" but "load image once → eval forms incrementally → inspect live values → redefine in place."

## Eval mechanism — the contract

This skill assumes a way to evaluate forms in a live Lisp image is available. The typical mechanism is an MCP server tool such as `eval_swank` from `lisp-mcp`, which talks to a long-running SBCL with a swank server. Anything that satisfies "I can send a form and get back the value, side effects visible to subsequent forms" works — a per-directory image (see `ramfjord-swank-image` for one such setup), a global dev image, or your own setup.

If no eval mechanism is available, surface that to the user before continuing — the rest of this skill assumes one exists.

The five habits below are ordered by how strongly they counter wrong reflexes. Every one of them counters a default I'd otherwise apply.

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

### Design-time triggers — when to inspect *before* writing code

The "inspect, don't guess" reflex is easy to apply when staring at a return value. It's harder to remember when *designing* — but that's where the biggest payoff is. Concrete triggers, each paired with the move that catches the failure:

- **About to subclass an existing class, or implement methods on an existing generic** → `(describe (find-class 'parent))` first. See which methods have defaults, which slots exist, what the convention is. Don't write `defmethod stream-read-char` while guessing whether `stream-peek-char` has a default — confirm.
- **About to delete a function you "know" is unused** → `(trace it)`, run the suite, confirm it isn't called. Empirical evidence beats "I read the call sites and it looks unused" every time, especially with generic functions and macroexpanded calls.
- **About to assert in a test how two pieces of code interact** → `(trace both-of-them)`, exercise the path once, read the call/return pattern. Then write the assertion against what you observed, not what you predicted.
- **About to hand-compute a value for a test expectation** (byte counts, string lengths, slot states) → don't. Build the object once, `(describe it)`, copy the actual value into the test. Hand-counting is slow and the arithmetic is exactly the class of thing the image already knows.
- **About to integrate with an unfamiliar API** (reader macros, format directives, condition system, ASDF hooks) → `trace` the entry points, run a minimal example, watch what gets called. Read-the-spec is fine for orientation; trace-the-call confirms you understood it.

Symptom that you skipped these: writing code, watching the test fail, then *only now* opening a REPL to figure out what the API actually does. If you're going to inspect to debug, inspect to design — it's the same effort earlier in the loop.

## 2. Errors carry information — read them, don't escape them

**Reflex to override:** treat an error as a wall and immediately go back to reading source.

**Do instead:** read the condition. The condition object carries the operator, the offending values, and often a hint at the right restart. Eval-via-MCP auto-aborts the debugger and returns the condition as text — so you don't get to interactively pick restarts, but you still get the diagnostic information for free, and that's almost always enough to fix the code and re-eval.

**Assume you are the only client.** The user typically attaches their editor (nvlime/Vlime) to swank only *after* you're done iterating, for review. During iteration, no one is sitting at an interactive debugger — swank is running unattended in a tmux session. Don't punt to the user with "pick restart 2" or "inspect the frame"; they can't, and waiting for them to attach mid-iteration just stalls the loop.

If you genuinely need an interactive restart or frame inspection (rare — usually you can reproduce by calling the offending function with crafted args and reading the returned condition), say so explicitly and ask the user to attach. Otherwise: read the condition, fix the code, reload, retry.

## 3. `trace` over print debugging — and over reading

**Reflex to override:** two reflexes, actually.
1. (When debugging) add `(format t "~A~%" x)` calls to see what's happening, forget to remove them, add more.
2. (When *understanding* code, not even debugging) read source files top-to-bottom to figure out which functions call which, with what arguments, in what order.

**Do instead:** `trace` the functions you care about, run the path once, read the recorded call/return pattern. `untrace` cleans up automatically.

`trace` is a **comprehension tool**, not just a debugging tool. Before changing how a piece of code is used, trace it and exercise the surrounding flow once — you'll see the actual call pattern instead of a predicted one. This is especially valuable for:

- Generic functions (which method actually fires?)
- Macroexpanded calls (the source doesn't show the call site)
- Callbacks dispatched through frameworks (ASDF, FiveAM, swank)
- "Is this function even reached?" questions before deletion or refactor

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

### Edit-then-load vs. define-at-REPL

Two ways a redefinition can land in the image: edit the file and `(load ...)`, or paste a `defun` straight into the REPL. They are *not* interchangeable.

- **Edit-then-load is the default for known changes.** You're going to write the definition to disk anyway. Writing it once (in the file) and reloading is one step; defining at the REPL first and then duplicating it into the file is two steps that can drift apart.
- **Define-at-REPL is for shape-uncertain exploration.** When you don't know the right signature yet and want to try three variants in 30 seconds, the REPL is the right tool — short feedback loop, no file churn. Once a shape is settled, write it to the file and stop typing it at the prompt.
- **Anti-pattern:** type a definition at the REPL "to test it", confirm it works, then re-type the same definition into the file. That's pure double-work — the next `(load ...)` would have given you the same confirmation and skipped the duplication.

Two concrete moves that make this work:

- **Bind expensive setup to a global**: `(defparameter *sample* (parse-big-thing "..."))`. Now you can poke at `*sample*` for an hour without re-parsing.
- **Use `defparameter`, not `defvar`, while developing**: `defvar` won't overwrite an existing binding, so re-evaling it does nothing — surprising and frustrating during iteration. Switch to `defvar` only when the value should genuinely persist across reloads.

## 5. Targeted tests over manual REPL poking, once requirements are defined

**Reflex to override:** once a function "looks right" at the REPL, move on. Or: re-run the whole test suite after every `(load ...)` and skim the output.

**Do instead:** when the requirements are concrete enough to name (this input should produce that output, this case should signal that condition), drive iteration through a small targeted test set — not eyeballed return values, not the whole suite.

The loop, per change:

1. **Pick or write the tests that pin down the change.** Usually 3-5, could be just 1 for simple changes: the new behavior, the obvious adjacent cases that could regress, and one negative case. Hold this set in mind for the duration of the iteration; don't re-derive it every reload.
2. **Run them once before changing the function.** They should fail (new behavior) or pass (regression guard). If a "should fail" test passes, it isn't testing what you think — fix the test before the code.
3. **Optionally: stub the function to return the expected value and re-run.** If the test still fails, the harness isn't exercising the path — stop and fix that. This step is cheap and catches the most embarrassing class of green-but-wrong tests. Skip it for trivial changes; do it whenever the test's wiring is non-obvious (new fixture, new assertion shape, new code path).
4. **Implement, `(load ...)`, re-run the targeted set.** Not the whole suite. The whole suite is fast in this repo, but running it every iteration trains you to skim — running 3-5 named tests trains you to actually read the result.
5. **Once the targeted set is green, run the full suite once** before considering the change done. Cheap insurance against regressions in code paths you didn't think to name.

```lisp
;; Targeted run — name the tests, don't pattern-match the suite
(fiveam:run! 'render-handles-empty-template)
(fiveam:run! 'render-escapes-html-by-default)
(fiveam:run! 'render-passes-through-when-escape-nil)

;; Full suite, once, at the end of the change
(asdf:test-system :elp)
```

**When this doesn't apply:** shape-uncertain exploration (§4's define-at-REPL carve-out). If you don't yet know what the function's signature or return shape should be, writing a test first locks in a guess. Poke at the REPL, settle the shape, *then* switch into the targeted-test loop. The trigger to switch is "I could state the requirement as an assertion" — once that's true, stop manual-testing and write the assertion.

## Cross-cutting: when to fall back to file-based workflow

REPL-driven dev is the default. Fall back to cold runs (`make test`, `sbcl --script`) only for:

- **Pre-merge verification** — one cold run before pushing/opening a PR, as a gate against image-drift bugs that warm runs can mask.
- Reproducing a CI failure.
- Anything where image cleanliness is part of what you're testing (e.g. "does this load from scratch").

You do **not** need a cold run per commit. During iteration: edit, `(load ...)`, run the suite warm, repeat. If a freshly-loaded warm image is green, the on-disk code is what was tested — the cold run isn't telling you anything new at that scale. Saving cold runs for the merge gate keeps the iteration loop tight; if pre-merge cold ever fails, bisecting a handful of small commits is cheap.

If you find yourself reaching for a cold run during normal iteration, that's a smell — the live-image workflow should be faster *and* give you more information.

## Code review is REPL work too

Reviewing Lisp without running it leaves the best tool on the table. Even in "read-only" review, the live image accelerates understanding:

- Call the function under review on a sample input — a real return value beats a predicted one.
- `(macroexpand-1 '(some-macro ...))` to see what a macro actually generates, instead of mentally simulating it.
- `(describe #'foo)` for signature, docstring, and where it's defined — faster than grep for "what is this."
- `(trace foo)` then exercise the surrounding code path to see *which* call sites hit it and with what args. Great for "is this function actually used the way the PR claims."
- For a refactor PR, eval both the old and new versions on the same inputs and diff the results.

The only review work that doesn't benefit is review *of code you can't load* (depends on something you don't have, or a different runtime). Otherwise: load the branch, warm an image, poke at it.

## MCP eval_swank transport gotchas

When sending forms via `eval_swank` (or any single-form MCP transport), two things bite repeatedly:

- **Em-dashes and other multi-byte characters used to fail with `Connection error: junk in string`.** Fixed in `lisp-mcp` (commit on `~/projects/lisp-mcp/lisp-mcp.lisp` switching the swank socket to binary + explicit UTF-8 encode/decode + byte-length headers). Kept here as a historical note: if you see "junk in string" again on `eval_swank`, suspect the lisp-mcp install is older than that fix, and as a stopgap use plain ASCII (`--` for an em-dash) in expressions sent through the tool until the install is updated.
- **`(in-package :foo)` inside a `progn` doesn't affect the rest of the same form.** The reader processes the whole form before any evaluation, so subsequent unqualified symbols get interned in the *current* package, not `:foo`. Either send `(in-package …)` as its own call, or use fully-qualified symbols (`elp::frob`) in the body.

Same root cause as the swank bootstrap reader-vs-eval gotcha — read happens before eval, always.

## When this skill doesn't apply

- Pure config edits to `.lisp` files that aren't code (rare but exists — some config languages use s-exprs).
- Editing this skill itself or other meta-files.
