---
name: ramfjord-plan-status
description: Report the status of plans under ./plans/ by mapping each to a branch/worktree and checking whether work is unstarted, in flight, paused, or merged. Use when the user asks "what's the status of the plans", "which plans are in flight", "is plan X started", or wants a roll-up before drafting/starting new work.
---

# ramfjord-plan-status

Tells the user, for each `./plans/*.md`, whether the corresponding work is unstarted, in flight, paused, or done. Pairs with `ramfjord-draft-plan` (authoring) and `ramfjord-start-task` (execution).

## Plan ↔ branch mapping

For a plan at `./plans/<slug>.md`, the branch is determined as follows, in order:

1. **Explicit `Branch:` line** in the plan file (anywhere, but conventionally near the top). Wins if present. Format: `Branch: <branch-name>` on its own line. Frontmatter `branch:` also accepted.
2. **Slug fallback**: branch name == file slug. `plans/add-retry.md` → branch `add-retry` → worktree `worktrees/add-retry/`.

Worktree path is always `./worktrees/<branch>/` (matches `ramfjord-start-task`).

If neither resolves to anything, the plan is **unstarted**.

## Status categories

For each plan, classify as one of:

- **unstarted** — no branch, no worktree. The plan is paper only.
- **in flight** — worktree exists at `./worktrees/<branch>/`. Active work.
- **paused** — branch exists (`git rev-parse --verify <branch>` succeeds) but no worktree directory. Someone removed the worktree without merging; work is parked.
- **merged** — branch is reachable from `main` (`git merge-base --is-ancestor <branch> main`) OR branch is gone and the plan's slug appears in a recent merge commit message / TODOs.md as completed. Prefer the ancestry check; the heuristic is a fallback.
- **unknown** — mapping resolved to a branch name but none of the above checks succeeded cleanly. Surface to the user, don't guess.

## Preflight

```bash
git rev-parse --show-toplevel
ls plans/ 2>/dev/null
git worktree list
git branch --list
```

If `./plans/` is missing or empty, say so and stop — nothing to report.

## Procedure

For each `./plans/*.md`:

1. Resolve branch via the mapping rules above. Note which rule fired (explicit vs slug) — useful when reporting ambiguity.
2. Check worktree existence: `test -d ./worktrees/<branch>`.
3. Check branch existence: `git rev-parse --verify <branch> 2>/dev/null`.
4. If branch exists, check merged: `git merge-base --is-ancestor <branch> main`.
5. Classify per the categories above.

Cross-reference `TODOs.md` if present — a `[WIP: <branch>]` marker corroborates "in flight"; absence of the marker for an in-flight branch is worth flagging.

## Reporting

Default to a compact table or list. Group by status, in this order: **in flight**, **paused**, **unstarted**, **merged**, **unknown**. Within each group, alphabetical by slug.

Include for each row: slug, branch (if different from slug), worktree path (if exists), and a one-line note for anything surprising (e.g., "branch resolved via slug fallback — consider adding `Branch:` to the plan", or "TODOs.md has no WIP marker for this branch").

Keep it terse. The user is scanning for "what should I do next," not reading prose.

## Sequencing hints (optional, when asked)

If the user asks "what should I work on next" or similar, layer on the **Related plans** sections from each plan file (see `ramfjord-draft-plan`):

- An **unstarted** plan whose related plans are all **merged** is ripe.
- An **unstarted** plan blocked on an **in flight** plan should wait.
- An **in flight** plan whose dependencies are **paused** is at risk — flag it.

Don't volunteer this analysis on a plain status request; it's more output than asked for. Offer it ("want me to suggest sequencing?") when the status alone doesn't answer the user's question.

## What this skill does NOT do

- Modify plans, branches, or worktrees. Read-only.
- Decide that a plan is "done" on its own — merged-to-main is the signal. If the user wants to mark a plan abandoned/superseded, that's a `draft-plan` edit, not a status concern.
- Create the `Branch:` linkage. That belongs in `start-task` (when starting from a plan) or in a manual edit.
