# ramfjord skills

My personal Claude Code skills for Lisp development against the [lisp MCP](https://github.com/ramfjord/lisp-mcp). A big part of why these exist is to train Claude to code in Lisp on my personal projects — REPL-driven, image-based, the way the language wants to be written rather than the edit-run-print habits Claude carries over from other languages.

## Install

This repo is both a Claude Code plugin and a marketplace pointing at itself. To install, register the marketplace and then install the plugin:

```
/plugin marketplace add ramfjord/claude-skills
/plugin install ramfjord@ramfjord
```

Skills land in your session namespaced as `ramfjord:coding-lisp`, `ramfjord:do-plan`, etc.

### Installing from a local clone

If you've cloned the repo and want to load your working copy (for development, or to use a fork without pushing):

```
git clone git@github.com:ramfjord/claude-skills.git ~/projects/claude-skills
```

Then in a Claude Code session:

```
/plugin marketplace add ~/projects/claude-skills
/plugin install ramfjord@ramfjord
```

The marketplace registration is global to your Claude Code config, so once added you can install/reload from any working directory. Edits to your local clone take effect on the next `/plugin reload` (or session restart).

## What's in here

Two intermingled groups, currently bundled together:

- **Lisp dev** — `ramfjord:coding-lisp`, `ramfjord:swank-image`. Habits and tooling for working in a live SBCL+swank image via the lisp MCP.
- **Workflow** — `ramfjord:draft-plan`, `ramfjord:start-task`, `ramfjord:do-plan`, `ramfjord:plan-status`, `ramfjord:merge-order`, `ramfjord:merge-worktree`. My specific plan/branch/worktree flow: draft a plan → start-task creates a branch+worktree → do-plan walks commits and edits the plan inline (decisions captured per-commit, staged with the code) → merge-worktree merges back to main and tears down the scaffolding.

The workflow skills assume my conventions (plans under `./plans/`, worktrees under `./worktrees/`, one swank image per worktree). They're not designed for general use yet.

## If you want to try the Lisp parts

The lisp skills are the most generally useful pieces here. `ramfjord:coding-lisp` and `ramfjord:swank-image` are adaptable on their own — fork and adjust any references to my workflow skills. They depend on the lisp MCP being installed.

## Future direction

Aspirationally, the lisp skills will be split out into their own repo so they can stand alone. Until then, the boundary is informal — and currently violated in one place: `ramfjord:merge-worktree` calls `ramfjord:swank-image`'s `cleanup-swank.sh` directly during teardown. The principled version would have workflow skills hand off cleanup via a marker-file registry rather than naming lisp skills, but with only one cleanup consumer today, that registry would be a one-entry indirection layer. Worth introducing when a second cleanup-needing skill shows up; until then, the direct coupling is the honest minimum.
