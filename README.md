# ramfjord skills

My personal Claude Code skills for Lisp development against the [lisp MCP](https://github.com/ramfjord/lisp-mcp). A big part of why these exist is to train Claude to code in Lisp on my personal projects — REPL-driven, image-based, the way the language wants to be written rather than the edit-run-print habits Claude carries over from other languages.

## What's in here

Two intermingled groups, currently bundled together:

- **Lisp dev** — `ramfjord-coding-lisp`, `ramfjord-swank-image`. Habits and tooling for working in a live SBCL+swank image via the lisp MCP.
- **Workflow** — `ramfjord-draft-plan`, `ramfjord-start-task`, `ramfjord-do-plan`, `ramfjord-plan-status`, `ramfjord-merge-order`, and (planned) `ramfjord-finish-task`. My specific plan/branch/worktree flow.

The workflow skills assume my conventions (plans under `./plans/`, worktrees under `./worktrees/`, one swank image per worktree). They're not designed for general use yet.

## If you want to try the Lisp parts

The lisp skills are the most generally useful pieces here. `ramfjord-coding-lisp` and `ramfjord-swank-image` are adaptable on their own — fork, drop the `ramfjord-` prefix, and adjust any references to my workflow skills. They depend on the lisp MCP being installed.

## Future direction

Aspirationally, the lisp skills will be split out into their own repo so they can stand alone. Until then, the boundary is informal — workflow skills shouldn't name lisp skills directly, and cleanup hooks between them go through marker-file conventions rather than direct invocation, to keep the seam clean for an eventual split.
