# ramfjord skills

My personal Claude Code skills for Lisp development against the [lisp MCP](https://github.com/ramfjord/lisp-mcp). A big part of why these exist is to train Claude to code in Lisp on my personal projects — REPL-driven, image-based, the way the language wants to be written rather than the edit-run-print habits Claude carries over from other languages.

## Install

This repo is both a Claude Code plugin and a marketplace pointing at itself. To install, register the marketplace and then install the plugin:

```
/plugin marketplace add ramfjord/claude-skills
/plugin install ramfjord@ramfjord
```

Skills land in your session namespaced as `ramfjord:coding-lisp`, `ramfjord:swank-image`.

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

- `ramfjord:coding-lisp` — habits for REPL-driven, image-based Lisp work.
- `ramfjord:swank-image` — set up and manage a per-directory SBCL+swank image wired to the lisp MCP.

Both depend on the lisp MCP being installed.
