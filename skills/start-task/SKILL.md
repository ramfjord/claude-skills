---
name: start-task
description: Start a new task from a plan in ./plans/ — creates a git branch + worktree under ./worktrees/, writes a CURRENT_PLAN.md marker stub identifying the plan, and prints a command to launch a new Claude session there with ramfjord:do-plan invoked. Use when the user says "start a task", "kick off X", "let's begin work on Y", or "I'm ready to start on this plan".
---

# ramfjord:start-task

Minimal mechanics for spinning up a new piece of work from an existing
plan. Planning happens on `main` in `./plans/<slug>.md` (drafted via
`ramfjord:draft-plan`); this skill carries that plan into a worktree
and prints a command to start working there.

This skill deliberately does only three things:

1. Create a branch and worktree from `main`.
2. Copy `./plans/<slug>.md` into the worktree as `CURRENT_PLAN.md`.
3. Print a launch command for a new Claude session in the worktree
   that invokes `ramfjord:do-plan` on the copied plan.

Tracking concerns — TODOs.md, plan↔branch linkage, merge ordering —
are deliberately *not* part of this skill. Use `ramfjord:merge-order`
to enqueue the branch separately if you want it in the queue.

## Inputs

- **Plan** — required. A path like `./plans/stream-input.md`, the
  slug `stream-input`, or any unambiguous reference to a file in
  `./plans/`. If ambiguous, list candidates and ask.
- **Branch name** — optional. Defaults to the plan slug. If the user
  gave one, use it verbatim.

## Preflight

Run from the project root (the main checkout, not an existing worktree):

```bash
git rev-parse --show-toplevel    # must succeed
git rev-parse --abbrev-ref HEAD  # warn if not on main
test -f plans/<slug>.md          # required — the plan must exist
```

If the plan file doesn't exist, stop and offer `ramfjord:draft-plan`.

If the plan file lacks a `## Commits` section, warn but don't block —
`ramfjord:do-plan` won't be able to walk it, but the user may want to
start anyway and add commits as they go.

If `./worktrees/<branch>` already exists or the branch already exists,
stop and ask.

Do **not** check or edit `.gitignore`. `CURRENT_PLAN.md` and
`worktrees/` may be ignored globally (`~/.config/git/ignore`) rather
than per-repo.

## Create the worktree

```bash
git worktree add -b <branch> ./worktrees/<branch> main
```

Branch from `main` explicitly, not whatever HEAD happens to be.

## Write the worktree marker

```bash
cat > ./worktrees/<branch>/CURRENT_PLAN.md <<EOF
Branch: <branch>
Plan source: ./plans/<slug>.md
EOF
```

`CURRENT_PLAN.md` is a tiny marker file (gitignored) that identifies
which plan this worktree is working on. It's not a copy of the plan
content — `ramfjord:do-plan` reads `plans/<slug>.md` directly via
the branch's working tree, edits it inline as commits land, and
stages those edits alongside the code. The marker exists so anyone
landing in the worktree can see what's being worked on without
needing to read `git log` or guess from the branch name.

## Hand off

Print, in this order:

1. Worktree path: `./worktrees/<branch>`
2. Branch name: `<branch>`
3. Plan source: `./plans/<slug>.md`
4. A launch command the user can paste to start a new Claude session
   in the worktree with `ramfjord:do-plan` invoked:

   ```
   (cd ./worktrees/<branch> && claude "/ramfjord:do-plan plans/<slug>.md")
   ```

   If you've seen the user use a different invocation style elsewhere
   in the session, adapt; otherwise the above is the safe default.

If the project is a Lisp project (has `.asd` files, `package.lisp`,
etc.), mention `ramfjord:swank-image` for spinning up the
per-worktree image — but don't invoke it automatically.

If the user wants the branch in the merge queue, mention
`ramfjord:merge-order` — don't invoke it automatically.

## What this skill does NOT do

- Draft or flesh out plans. That's `ramfjord:draft-plan`.
- Edit `TODOs.md`. Track work however you like, separately.
- Link plan files to branches. The `Plan source:` line in
  `CURRENT_PLAN.md` is the only connection; if you want richer
  tracking, edit the plan in `./plans/` by hand.
- Enqueue in `MERGE_ORDER.md`. Use `ramfjord:merge-order` separately.
- Mark tasks done or merge branches. Use `ramfjord:merge-worktree`
  for closing out a worktree: it merges the branch back to main and
  tears down the worktree + swank image.
- Stack branches. All branches start from `main`.
- Touch `main` with any commits. The skill makes no commits at all —
  the worktree is empty of changes until the user starts working.
- Launch the new Claude session itself. It just prints the command;
  the user runs it.
- Execute the plan. That's `ramfjord:do-plan`, invoked by the launch
  command in the new session.
