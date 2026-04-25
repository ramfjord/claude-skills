---
name: ramfjord-start-task
description: Start a new task from an idea or TODO item — creates a git branch + worktree under ./worktrees/, marks the item in-progress in TODOs.md (committed on the new branch), and seeds a freeform CURRENT_PLAN.md inside the worktree. Use when the user says "start a task", "kick off X", "let's begin work on Y", or hands over an idea/TODO they want to work on next.
---

# ramfjord-start-task

Mechanics for spinning up a new piece of work. The skill does the boring setup; the user (with Claude's help in conversation) does the thinking.

## What this skill does

1. Pick a branch name.
2. Create a worktree under `./worktrees/<branch>` from `main`.
3. Inside the worktree: edit `TODOs.md` to mark the item in-progress with the branch name, commit that as the first commit on the branch.
4. Write a freeform `CURRENT_PLAN.md` at the worktree root (gitignored, uncommitted).
5. `cd` into the worktree (or tell the user to) and hand off.

## Inputs

- **Idea / TODO text** — required. Either a short description ("add retry to the ingest worker"), a verbatim line from `TODOs.md`, or a path/reference to a plan under `./plans/`.
- **Plan** — optional. A path like `./plans/add-retry.md` or just the slug `add-retry`. If given, the plan's slug becomes the default branch name and the plan file is linked to the branch (see *Linking a plan* below).
- **Branch name** — optional. If the user gave one, use it verbatim. Otherwise: if started from a plan, use the plan slug. Otherwise derive from the idea: lowercase, kebab-case, 3–5 words capturing the essence. Strip leading verbs like "add/fix/update" only if the result is still descriptive.

## Preflight

Run from the project root (the main checkout, not an existing worktree):

```bash
git rev-parse --show-toplevel    # must succeed
git rev-parse --abbrev-ref HEAD  # warn if not on main
```

If `./worktrees/` or `CURRENT_PLAN.md` aren't in `.gitignore`, point that out to the user — per project convention these should be gitignored. Don't silently edit `.gitignore`; ask.

If `./worktrees/<branch>` already exists or the branch already exists, stop and ask.

## Create the worktree

```bash
git worktree add -b <branch> ./worktrees/<branch> main
```

Branch from `main` explicitly, not whatever HEAD happens to be.

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

This commit rides with the branch — merging the branch is what updates main's TODO list. No commit on main.

## Linking a plan (only if started from one)

If the task was started from a plan at `./plans/<slug>.md`, record the branch in the plan file so `ramfjord-plan-status` can map the two. Do this on **main**, not on the branch — `plan-status` runs from main and needs to see the linkage before the branch is ever merged.

In the main checkout (not the worktree):

1. Read the plan file. If it already has a `Branch:` line or frontmatter `branch:` field, leave it alone (the user set it deliberately).
2. Otherwise, add a `Branch: <branch>` line near the top of the plan (after the H1 title, before the first section).
3. Commit just that one file:

   ```bash
   git add plans/<slug>.md
   git commit -m "Link plan: <slug> -> <branch>"
   ```

This is the **only** edit this skill makes to `main`, and it's metadata-only — no work content. Skip entirely when the task isn't tied to a plan.

Also reference the plan from `CURRENT_PLAN.md` (next step) so the worktree points back at its source plan.

## Seed CURRENT_PLAN.md

Write `CURRENT_PLAN.md` at the worktree root. Freeform — a starting scaffold is fine but don't be prescriptive. Something like:

```markdown
# <idea>

Branch: <branch>
Plan: <./plans/slug.md, if started from one — else omit>

## Goal

<one or two lines — what does "done" look like?>

## Notes

```

Do **not** `git add` it. It's gitignored per project convention.

## Hand off

Tell the user:
- Worktree path
- Branch name
- That `CURRENT_PLAN.md` is ready to fill in

If the project is a Lisp project (has `.asd` files, `package.lisp`, etc.), mention `ramfjord-swank-worktree-image` for spinning up the per-worktree image — but don't invoke it automatically.

## What this skill does NOT do

- Flesh out the plan. That's a conversation, not a script.
- Mark tasks done or merge branches. Separate `finish-task` skill (TBD).
- Touch `main` with work content. The only main edit it makes is the one-line `Branch:` link in the plan file (see *Linking a plan*), and only when started from a plan.
