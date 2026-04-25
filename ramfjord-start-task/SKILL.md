---
name: ramfjord-start-task
description: Start a new task from an existing CURRENT_PLAN.md drafted on main — creates a git branch + worktree under ./worktrees/, marks the item in-progress in TODOs.md, moves CURRENT_PLAN.md into the worktree, and enqueues the branch in plans/MERGE_ORDER.md. Use when the user says "start a task", "kick off X", "let's begin work on Y", or "I'm ready to start on this plan".
---

# ramfjord-start-task

Mechanics for spinning up a new piece of work. Planning happens on `main` (in `CURRENT_PLAN.md` and optionally `./plans/<slug>.md`); this skill carries that planning into a worktree and announces the work in the merge queue.

## What this skill does

1. Verify a `CURRENT_PLAN.md` exists in the main checkout — that's the planning artifact this skill operates on.
2. Pick a branch name.
3. Create a worktree under `./worktrees/<branch>` from `main`.
4. Inside the worktree: edit `TODOs.md` to mark the item in-progress with the branch name, commit on the branch.
5. **Move** `CURRENT_PLAN.md` from main into the worktree (no copy left behind on main).
6. If started from a plan in `./plans/`, link the plan file to the branch (commit on main).
7. Enqueue the branch in `./plans/MERGE_ORDER.md` (commit on main).
8. `cd` into the worktree (or tell the user to) and hand off.

## Inputs

- **Idea / TODO text** — required. Either a short description, a verbatim line from `TODOs.md`, or a path/reference to a plan under `./plans/`.
- **Plan** — optional. A path like `./plans/add-retry.md` or just the slug `add-retry`. If given, the plan's slug becomes the default branch name and the plan file is linked to the branch (see *Linking a plan* below).
- **Branch name** — optional. If the user gave one, use it verbatim. Otherwise: if started from a plan, use the plan slug. Otherwise derive from the idea: lowercase, kebab-case, 3–5 words capturing the essence. Strip leading verbs like "add/fix/update" only if the result is still descriptive.
- **Queue position** — optional. Where to insert in `MERGE_ORDER.md`. Default: end. Accepts "front", "before <branch>", "after <branch>", "position N".

## Preflight

Run from the project root (the main checkout, not an existing worktree):

```bash
git rev-parse --show-toplevel    # must succeed
git rev-parse --abbrev-ref HEAD  # warn if not on main
test -f CURRENT_PLAN.md          # required — see below
```

**`CURRENT_PLAN.md` must already exist in the main checkout.** This skill does not seed one — the user is expected to have drafted it on main as part of planning. If missing, stop and tell the user to create it first (and offer `ramfjord-draft-plan` if they want a durable plan as well).

If `./worktrees/`, `CURRENT_PLAN.md`, or `./plans/MERGE_ORDER.md`'s parent dir aren't set up per project convention (worktrees and CURRENT_PLAN.md gitignored; `plans/` tracked), point that out. Don't silently edit `.gitignore`; ask.

If `./worktrees/<branch>` already exists or the branch already exists, stop and ask.

## Create the worktree

```bash
git worktree add -b <branch> ./worktrees/<branch> main
```

Branch from `main` explicitly, not whatever HEAD happens to be. Always from main, regardless of merge queue position — branches do not stack.

## Update TODOs.md (committed on the branch)

Inside the worktree:

- If `TODOs.md` exists and contains a line matching the idea, append ` [WIP: <branch>]` to that line.
- If it exists but the idea isn't there, add a new line under an `## In progress` section (create the section if missing): `- <idea> [WIP: <branch>]`.
- If it doesn't exist, create it with:
  ```
  # TODOs

  ## In progress

  - <idea> [WIP: <branch>]
  ```

Then commit *only* `TODOs.md`:

```bash
git add TODOs.md
git commit -m "Start: <idea>"
```

This commit rides with the branch — merging the branch is what updates main's TODO list.

## Move CURRENT_PLAN.md into the worktree

The user's planning notes live in `CURRENT_PLAN.md` on main. Move them into the worktree so main is free for the next task's planning:

```bash
mv CURRENT_PLAN.md ./worktrees/<branch>/CURRENT_PLAN.md
```

It stays gitignored on both sides — no commits. If it doesn't already include a `Branch:` line, add one near the top so the worktree's notes are self-describing. If started from a plan, also add `Plan: ./plans/<slug>.md`.

## Linking a plan (only if started from one)

If the task was started from a plan at `./plans/<slug>.md`, record the branch in the plan file so `ramfjord-plan-status` can map the two. Do this on **main**, not on the branch — `plan-status` runs from main and needs to see the linkage before the branch is ever merged.

In the main checkout:

1. Read the plan file. If it already has a `Branch:` line or frontmatter `branch:` field, leave it alone.
2. Otherwise, add a `Branch: <branch>` line near the top of the plan (after the H1 title, before the first section).
3. Commit just that one file:

   ```bash
   git add plans/<slug>.md
   git commit -m "Link plan: <slug> -> <branch>"
   ```

Skip entirely when the task isn't tied to a plan.

## Enqueue in MERGE_ORDER

Use `ramfjord-merge-order` to add the new branch to `./plans/MERGE_ORDER.md` on main. Default to the end of the queue; honor a user-specified position (front, before/after a sibling, etc.).

This is the second main-touching commit and, like the plan link, is metadata-only.

## Hand off

Tell the user:
- Worktree path
- Branch name
- That `CURRENT_PLAN.md` has been moved into the worktree
- Queue position in `MERGE_ORDER.md`

If the project is a Lisp project (has `.asd` files, `package.lisp`, etc.), mention `ramfjord-swank-worktree-image` for spinning up the per-worktree image — but don't invoke it automatically.

## What this skill does NOT do

- Draft or flesh out plans. That's `ramfjord-draft-plan` and conversation.
- Seed `CURRENT_PLAN.md`. The user writes it on main before starting.
- Mark tasks done or merge branches. Separate `finish-task` skill (TBD).
- Stack branches. All branches start from `main`, regardless of queue position.
- Touch `main` with work content. The only main edits are: the optional plan-link commit, and the merge-order enqueue commit. Both are metadata-only.
