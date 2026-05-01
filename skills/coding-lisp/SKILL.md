---
name: coding-lisp
description: Use whenever editing, reading, debugging, OR DESIGNING Lisp-family code (Common Lisp, Scheme, Clojure, Emacs Lisp — any .lisp/.cl/.scm/.ss/.rkt/.clj/.cljs/.el file). Activate during design discussions ("how should we structure…", "could we…", "what's the right way to…") about Lisp code, not just hands-on edits — the skill's perspective is most valuable *before* committing to an approach. Encodes REPL-driven development habits that distinguish good Lisp work from edit-run-print loops, counters reflexes carried over from non-image-based languages, and primes you to reach for code-as-data designs that are cheap in Lisp and expensive everywhere else.
---

# ramfjord:coding-lisp

Lisp is a *REPL-driven* language. The default mode of work is not "edit file → run → read output" but "load image once → eval forms incrementally → inspect live values → redefine in place."

## Eval mechanism — the contract

This skill assumes a way to evaluate forms in a live Lisp image is available. The typical mechanism is an MCP server tool such as `eval_swank` from `lisp-mcp`, which talks to a long-running SBCL with a swank server. Anything that satisfies "I can send a form and get back the value, side effects visible to subsequent forms" works — a per-directory image (see `ramfjord:swank-image` for one such setup), a global dev image, or your own setup.

If no eval mechanism is available, surface that to the user before continuing — the rest of this skill assumes one exists.

The habits below are ordered by how strongly they counter wrong reflexes. Every one of them counters a default I'd otherwise apply. The first two are about **what to design** — code-as-data and declaration-form shape are both Lisp differentiators, and both are moves you'll most often miss if you carry over reflexes from non-Lisp languages. They belong at plan-time as much as edit-time: a misframing at this layer will commit you to weeks of awkward code that the right framing would have collapsed. The remaining five are about **how to work** in a live image. Same root cause throughout: code is data, the image is live, so the cheap moves are different.

## 1. Reach for code-as-data — at plan time, not just edit time

**Reflex to override:** treat code as text-or-AST-objects you have to construct, parse, and serialize by hand. Specifically, treat "produce Lisp behavior from input" as a parsing-then-codegen pipeline that builds source as text, and treat "expose Lisp behavior as a result" as a function that runs the code, with no first-class artifact representing what ran.

**Do instead:** before committing to a design, ask the same question in **both directions**:

- *Does the* **output** *of this problem have code shape?* — Then build/return a sexp. Don't compose source as text and `read-from-string` it; backquote constructs sexps directly. Don't hide the generated form behind an opaque "render" call; expose it as a first-class return value so callers can inspect, print, copy, or eval it.
- *Does the* **input** *of this problem have code shape?* — Then let the **standard reader** consume it. Don't tokenize-then-assemble-source-string-then-read-from-string; that's three passes for a job the reader does in one. The variation point is a custom stream (`sb-gray:fundamental-character-input-stream`) that synthesizes characters for the reader to walk — template syntax, embedded DSLs, anything where "the eventual sexp shape" is roughly the right answer.

Both directions are the same insight: `read`, `eval`, `print`, `defmacro`, backquote, `#.` are sized for daily use. Reach for them.

### Concrete patterns

- **Sexps as public artifacts (output side).** When a tool's job is "compute then run," return the computed sexp as a first-class value and have the run path be `(eval (compute …))`. Two payoffs: inspection is free (`prin1` the form into a `--print` flag, log it, paste it into the REPL); the eval path stops being a black box. In non-homoiconic languages, "show me the code that ran" is a debug-renderer project; in Lisp it's one line.

- **The reader is your parser (input side).** When input has sexp shape, `read` from a stream — don't write a parser, don't define a grammar, don't reach for a serialization library. Files of data sexps are the simplest, most common case:

  ```lisp
  (with-open-file (s path) (read s))                  ; one top-level form
  (with-open-file (s path)
    (loop for f = (read s nil :eof) until (eq f :eof)
          collect f))                                  ; multiple
  ```

  You get comments, symbols-as-enums, structural nesting, and round-trip via `prin1` for free. Common uses: configs, asset definitions, fixtures, anything Rust would reach for Ron / serde / a custom parser to handle. For inputs that *embed* Lisp inside non-Lisp (templates, DSLs that escape into surrounding text), the same idea generalizes via a custom stream that synthesizes characters for the standard reader (`sb-gray:fundamental-character-input-stream`) — but most projects only need the file-of-sexps case.

- **`read` parses, `eval` executes — keep the line clean.** For data files especially: `read` the form, destructure it, dispatch on it. `eval`-ing data turns "load this config / asset / fixture" into "run arbitrary code from a file," which is almost never what you want and ties the format's meaning to whichever functions happen to be in scope.

- **Anti-pattern: building Lisp source as text, then `read-from-string`-ing it back.** If you're assembling strings like `"(do-thing ~D)"` and then re-parsing them, you're doing the reader's job in two awkward stages. The fix is backquote: `` `(do-thing ,n) `` constructs the sexp directly. (Niche, but worth naming — it's the input-side cousin of "hide the generated form behind opaque execution.")

- **One source, two roles via a registering macro.** When a definition needs to live *both* as a top-level `defun` (for REPL ergonomics, `M-.`, individual eval) *and* as a sexp embedded inside generated code, write a macro that does both from one source form:

  ```lisp
  (defvar *helper-sources* '())
  (defmacro define-helper (name lambda-list &body body)
    `(progn
       (setf *helper-sources*
             (append (remove ',name *helper-sources* :key #'car)
                     (list '(,name ,lambda-list ,@body))))
       (defun ,name ,lambda-list ,@body)))
  ```

  Codegen splices the registered sources into a `labels` block. In a non-Lisp language the equivalent is "string-template the source" or "give up and duplicate."

- **`#.` to bake values into source at read time.** When a generated form references a defconstant whose value matters but whose symbol shouldn't leak, write `#.+the-constant+`. The reader substitutes the value before any later step sees the form. Niche; the right tool when "I want the number, not the binding."

- **Round-trip the form to test self-containment.** For any function that returns a sexp meant to be eval-able outside its construction context, the cheapest test is `(eval (read-from-string (with-output-to-string (s) (prin1 form s))))` — possibly with `*package*` bound to whatever a consumer would use. If the round-trip's behavior diverges from direct `(eval form)`, the form has a hidden lexical/package dependency.

### Triggers — when to invoke this lens

**Self-cues (questions to ask at plan time, before settling on an approach):**

- Does the input have sexp shape? → `read` it, don't parse it.
- Does the output have code shape? → return a sexp, expose it; don't hide behind opaque execution.
- Am I about to write Lisp source as text? → backquote builds the sexp directly.
- Am I about to `read-from-string` something I constructed? → backquote, or read from a stream.
- Is this definition appearing in two places? → registering macro can collapse runtime + codegen.
- Would I want to inspect/test the form a function generates? → make the form the return value, not the side effect.

**User-cues (phrasings that signal a code-as-data move is what they actually want):**

- "Could we just *put the definition of this here*?" → registering macro for one source, two roles.
- "Can we print the code that would run?" / "I'd like to see what gets eval'd." → return the sexp, expose it.
- "It would be nice if this were standalone / runnable / pasteable." → wrap with `labels`/`let` so the form carries its own bindings; print it.
- "Why is this referenced in two places?" → if those places are runtime and codegen, a macro can collapse them.

### Cost: don't reach for it for problems that don't need it

Code-as-data is the *cheap option in Lisp*, not the *first option for everything*. If the answer is a plain function and a plain call, write that. The trigger is "the problem has code-shaped input or output, or a duplication that crosses runtime/codegen layers" — not "I'm in Lisp so let me use macros." Macros and `eval` are everyday tools but still cost readability; reach for them when the alternative is fighting the language.

## 2. Make declaration forms describe what they declare, not how they're built

**Reflex to override:** ship the data structure as the surface form. When a feature needs N entries of "key plus computed value," reach for an alist or list of conses literally — and put the lambdas, the cons-pairs, the quasi-unquote splicing right there in the user-facing form. The reader sees the construction mechanism every time they read an entry.

**Do instead:** when the surface form is a *declaration* (a thing readers are supposed to recognize as "this is one of those"), wrap it in a macro that absorbs the construction mechanism. The macro is small. The payoff is that every visible token in the call site does work toward the meaning of the declaration, instead of toward how it's stored.

Concrete before/after — a six-line macro buys per-entry clarity across every declaration:

```lisp
;; Before — surface form describes how the entry is stored.
(defparameter *derived-fields*
  `((:compose-file
     . ,(lambda (s g)
          (format nil "~A/~A" (getf g :install-base) (getf s :name))))
    (:source-dir
     . ,(lambda (s g)
          (declare (ignore g))
          (format nil "services/~A" (getf s :name))))
    (:unit
     . ,(lambda (s g)
          (declare (ignore g))
          (getf s :unit)))
    ...))

;; After — surface form describes what the field is.
(define-service-field :compose-file
  (format nil "~A/~A" (getf globals :install-base) (svc-field :name)))
(define-service-field :source-dir
  (format nil "services/~A" (svc-field :name)))
(define-service-field :unit)   ; bare form is the limit of the general form
```

The "before" surface form contains: alist construction (`'((... . ...) ...)`), quasi-unquote splices (`,(lambda ...)`), the lambda keyword and gensym arg names (`s`, `g`), `(declare (ignore g))` markers in bodies that don't need globals, and `(getf s ...)` references that mention `s` only because the closure needs it. None of those say anything about *the field*. The reader has to subtract them to find the content. The "after" form has no token that doesn't say something about the specific field being declared.

### The principle

**Every visible mechanism in a surface form should carry meaning relevant to that form's purpose.** All code is mechanism — that's not the issue. The issue is *whose mechanism is on display*: the implementation's (how the value is stored, what arguments the closure happens to take, how entries are glued into a structure), or the form's (what this declaration is, what it computes). The macro's job is to absorb the implementation's mechanism in one place so call sites are content-only.

### Symptoms that point to this move

- **Positional gensym variable names in call-site bodies** (`s`, `g`, `x`, `acc`). They name nothing; they exist because the implementation chose to expose those parameters. The macro can give them real names once, in one place — or replace them with helpers (`svc-field`, `global`) that close over them.

- **`(declare (ignore X))` in bodies that don't need X.** Loud irrelevance. Each occurrence makes the reader pay attention to the absence of a thing. Replace with `ignorable` once inside the macro; bodies that don't use the parameter become silent. Silent absence is free; declared absence is taxed.

- **Repeated tokens that don't differentiate adjacent entries.** If every entry has the same `,(lambda (s g) ...)` shell with the same `(declare (ignore g))` and the same `(getf s ...)` references — and the only token that varies is the keyword — then everything *except* that keyword is scaffolding. Move it into the macro.

- **A "trivial" case that looks syntactically different from the "interesting" case.** If a no-op passthrough requires `(:foo . ,(lambda (s g) (declare (ignore g)) (getf s :foo)))` while a computed entry is similar with a different body, the trivial form should be the *limit* of the general form, not a separate ritual. `(define-service-field :foo)` and `(define-service-field :foo (some-form))` share a shape; the bare form is the interesting form in miniature.

- **Direct alist/plist construction at the top level when the entries are conceptually separate declarations.** Each entry is a thing the reader thinks about as a unit; the implementation's choice to glue them together as one literal is incidental. A series of `(define-X ...)` forms reads as a series of declarations; a single quoted list reads as one big literal that happens to contain N things.

### What this is not

This is **not** "wrap everything in a macro." Macros cost readability — they introduce a layer between source and behavior that has to be macroexpanded to understand. The trigger is specifically: **a recurring shape where the same scaffolding appears around varying content, and the scaffolding has no meaning at the call site**. If your data structure is genuinely just a list of pairs and the bodies are uniform `getf`s, an alist is fine. The smell is when bodies are non-trivial *and* every body shares the same wrapping ritual *and* a reader has to subtract that ritual to find what each entry means.

This is also not about line count. The macro can be five lines; the entries might save two lines each. The win is per-entry readability, not total-LoC.

### Self-cue

When designing a form that someone will read as "one of these declarations," ask: **does every visible token in the form say something specific about this particular declaration?** If tokens recur across entries (lambda wrappers, ignore declarations, gensym arg references, alist construction syntax) and only the keyword varies, those recurring tokens belong inside a macro, not in the surface form.

The taste cue when reading: if you find yourself mentally editing out scaffolding to see what each entry *means*, that's the smell. If you read a form and feel like every token is doing work, that's the inverse signal — the form fits its meaning.

## 3. Inspect, don't guess

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

## 4. Errors carry information — read them, don't escape them

**Reflex to override:** treat an error as a wall and immediately go back to reading source.

**Do instead:** read the condition. The condition object carries the operator, the offending values, and often a hint at the right restart. Eval-via-MCP auto-aborts the debugger and returns the condition as text — so you don't get to interactively pick restarts, but you still get the diagnostic information for free, and that's almost always enough to fix the code and re-eval.

**Assume you are the only client.** The user typically attaches their editor (nvlime/Vlime) to swank only *after* you're done iterating, for review. During iteration, no one is sitting at an interactive debugger — swank is running unattended in a tmux session. Don't punt to the user with "pick restart 2" or "inspect the frame"; they can't, and waiting for them to attach mid-iteration just stalls the loop.

If you genuinely need an interactive restart or frame inspection (rare — usually you can reproduce by calling the offending function with crafted args and reading the returned condition), say so explicitly and ask the user to attach. Otherwise: read the condition, fix the code, reload, retry.

## 5. `trace` over print debugging — and over reading

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

## 6. Redefine on the fly — the warm image is the point

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

This is *why* REPL-driven dev is fast: you pay setup cost once and iterate on top of it.

### Per-form helpers: `claude-tools:eval-form-at` and `claude-tools:reload-form`

The `ramfjord:swank-image` bootstrap preloads two helpers in every image, in the `claude-tools` package:

- **`(claude-tools:eval-form-at FILE LINE &optional COL)`** — read the form starting at `FILE:LINE:COL` and eval it; returns the value. The C-x C-e / C-M-x analogue: ask "what does *this* form return, given the file's current state" without retyping the form or restructuring it into a one-off blob. `LINE` is 1-based; `COL` defaults to 0 (leading whitespace is fine, the reader skips it).
- **`(claude-tools:reload-form FILE 'NAME)`** — find the top-level form in `FILE` whose head is `NAME` and re-eval it. The C-c C-c analogue: redefine one defun without `(load ...)`-ing the whole file (which would re-run all top-level side effects — `defparameter`s clobbering bindings you care about, `defpackage`s, setup calls).

When to reach for which:

- **Whole-file reload** (`(load "scratch.lisp")`) — scratch files where everything is meant to re-run, or source files with no side-effecting top-level forms you care about.
- **`claude-tools:reload-form`** — source files where you want to redefine *one* function without disturbing the rest of the image's state. The common case once you've stopped using `(load ...)` reflexively.
- **`claude-tools:eval-form-at`** — value-checking. You wrote `(parse-config *sample*)` somewhere in a file (test, scratch, comment block) and want to see what it returns *now*, with the image's current state. No need to type the form into eval_swank or wrap it in a `progn` with setup.

Both read with the live image's reader, so reader macros, `#|...|#`, `#\(`, `#+sbcl`, custom readtables — all handled. If the file lives in a non-`cl-user` package, bind `*package*` around the call: `(let ((*package* (find-package :elp))) (claude-tools:eval-form-at "src/foo.lisp" 42))`.

Cost-of-line-numbers caveat: `claude-tools:eval-form-at`'s line/col arguments go stale fast when you're editing the file. Fine for one-off probes (the form is usually gone by the next iteration). For repeated reloads of the same defun across many edits, prefer `claude-tools:reload-form` — names are stable across edits.

### Edit-then-load vs. define-at-REPL

Two ways a redefinition can land in the image: edit the file and `(load ...)`, or paste a `defun` straight into the REPL. They are *not* interchangeable.

- **Edit-then-load is the default for known changes.** You're going to write the definition to disk anyway. Writing it once (in the file) and reloading is one step; defining at the REPL first and then duplicating it into the file is two steps that can drift apart.
- **Define-at-REPL is for shape-uncertain exploration.** When you don't know the right signature yet and want to try three variants in 30 seconds, the REPL is the right tool — short feedback loop, no file churn. Once a shape is settled, write it to the file and stop typing it at the prompt.
- **Anti-pattern:** type a definition at the REPL "to test it", confirm it works, then re-type the same definition into the file. That's pure double-work — the next `(load ...)` would have given you the same confirmation and skipped the duplication.

Two concrete moves that make this work:

- **Bind expensive setup to a global**: `(defparameter *sample* (parse-big-thing "..."))`. Now you can poke at `*sample*` for an hour without re-parsing.
- **Use `defparameter`, not `defvar`, while developing**: `defvar` won't overwrite an existing binding, so re-evaling it does nothing — surprising and frustrating during iteration. Switch to `defvar` only when the value should genuinely persist across reloads.

## 7. Targeted tests over manual REPL poking, once requirements are defined

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

**When this doesn't apply:** shape-uncertain exploration (§6's define-at-REPL carve-out). If you don't yet know what the function's signature or return shape should be, writing a test first locks in a guess. Poke at the REPL, settle the shape, *then* switch into the targeted-test loop. The trigger to switch is "I could state the requirement as an assertion" — once that's true, stop manual-testing and write the assertion.

## Cross-cutting: when to fall back to file-based workflow

REPL-driven dev is the default. Fall back to cold runs (`make test`, `sbcl --script`) only for:

- **Pre-merge verification** — one cold run before pushing/opening a PR, as a gate against image-drift bugs that warm runs can mask.
- Reproducing a CI failure.
- Anything where image cleanliness is part of what you're testing (e.g. "does this load from scratch").

You do **not** need a cold run per commit. During iteration: edit, `(load ...)`, run the suite warm, repeat. If a freshly-loaded warm image is green, the on-disk code is what was tested — the cold run isn't telling you anything new at that scale. Saving cold runs for the merge gate keeps the iteration loop tight; if pre-merge cold ever fails, bisecting a handful of small commits is cheap.

If you find yourself reaching for a cold run during normal iteration, that's a smell — the live-image workflow should be faster *and* give you more information.

## Cross-cutting: prefer named iteration when one fits

`loop` is the swiss-army knife of CL iteration, and reflexes carried
over from non-Lisp languages tend to reach for it for everything. But
many `loop` forms have a one-word equivalent that's shorter to write
and easier to read: the *intent* is in the name (`mapcar` =
"transform each", `every` = "do they all satisfy") instead of buried
in `for ... collect ...` syntax.

When you write `loop`, ask whether one of these fits:

| Pattern                                        | Use instead    |
|------------------------------------------------|----------------|
| `(loop for x in xs collect (f x))`             | `(mapcar #'f xs)` |
| `(loop for x in xs append (f x))`              | `(mapcan #'f xs)` |
| `(loop for x in xs when (p x) collect x)`      | `(remove-if-not #'p xs)` |
| `(loop for x in xs unless (p x) collect x)`    | `(remove-if #'p xs)` |
| `(loop for x in xs always (p x))`              | `(every #'p xs)` |
| `(loop for x in xs never (p x))`               | `(notany #'p xs)` |
| `(loop for x in xs sum (f x))`                 | `(reduce #'+ xs :key #'f)` |
| `(loop for x in xs do (side-effect x))`        | `(mapc #'... xs)` or `dolist` |

`loop` *is* the right tool when:

- Iterating hash-tables (`loop for k being the hash-keys ...`) —
  `maphash` accumulates via side-effect, which is uglier.
- Walking a plist with `by #'cddr` — pair-stride needs the explicit
  step, no built-in higher-order alternative.
- Multiple parallel collections accumulating different shapes
  (`collect ... and collect ...`).
- Stateful iteration with explicit mutation (argument parsing,
  early termination on a sentinel, etc.).

**Self-cue:** when you find yourself writing `(loop for x in xs ...)`
with a single body, pause and ask whether `mapcar` / `remove-if` /
`every` says it more clearly. The answer is usually yes.

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
