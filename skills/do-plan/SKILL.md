---
name: do-plan
description: Walk a plan's Commits list one at a time — implement, verify, show diff, get user approval, append decisions to the plan, commit plan + code together, repeat. Use when invoked with a plan path (typically launched by ramfjord:start-task in a fresh worktree session), or when the user says "work the plan", "do the plan", "continue the plan", "next commit", or "resume".
---

# ramfjord:do-plan

Execute a plan by walking its `## Commits` section one commit at a
time, gating each `git commit` on user approval. The plan file itself
is a *living* document — decisions made during implementation get
appended to the relevant commit's entry and committed alongside the
code change. By the time a branch reaches `ramfjord:merge-worktree`,
its plan reflects what actually happened.

This skill is the implementation-side counterpart to
`ramfjord:draft-plan`. The drafter sized the work into reviewable
commits; this skill walks them.

## What this skill does

1. Read the plan path the user gave (typically `plans/<slug>.md`)
   and parse its `## Commits` section into an ordered list.
2. Find the first unchecked commit (skip ones already marked `✅`).
3. For each remaining commit, in order:
   a. Announce which commit is next; show its title and *Verify:* line.
   b. Implement it.
   c. Run the verification step.
   d. Append a `**Decisions:**` block to that commit's entry in the
      plan file if non-trivial decisions were resolved during
      implementation; mark the entry `✅`.
   e. Show the diff (code + plan edit) and a proposed commit message.
   f. **Wait for user approval** before committing. Never auto-commit.
   g. On approval: `git commit` (staging plan edit alongside code).
   h. Continue to the next commit, or stop if the user wants to pause.

## Inputs

- **Plan path** — required. Typically `plans/<slug>.md` in the
  current repo. The launch command from `ramfjord:start-task` passes
  this explicitly. The worktree's `CURRENT_PLAN.md` (a gitignored
  marker stub) is *not* the plan and is not read by this skill.

## Preflight

```bash
git rev-parse --show-toplevel    # must be in a git repo
git rev-parse --abbrev-ref HEAD  # capture branch — should not be main
test -f <plan-path>              # plan must exist (and be tracked)
```

If the current branch is `main` (or the project's primary branch),
warn loudly and ask before proceeding — committing plan work directly
to main is almost always wrong. Honor the user's answer.

The plan file is expected to be a tracked file in the repo (typically
`plans/<slug>.md`). Edits to it land in commits alongside the code,
so it must not be gitignored.

If the plan file lacks a `## Commits` section, stop and offer to
draft commits collaboratively (and update the plan in place).

If the working tree has uncommitted changes that don't belong to the
current commit-in-progress, surface them before doing anything else.
Don't silently fold them in.

### Match relevant skills first

Before starting any commit, scan the available-skills list (in the
system reminder) for skills whose trigger conditions fire on this
repo or plan. Signals to look at:

- File extensions in the repo (`.lisp`/`.cl` → `ramfjord:coding-lisp`,
  `.ipynb` → notebook skills, etc.).
- Plan or commit text mentioning a domain a skill covers (REPL, swank,
  worktree image, Claude API, security review).
- The kind of work the next commit involves (editing code in language
  X → that language's skill, if one exists).

If any skill matches, **invoke it via the Skill tool now** — don't
defer it to "if I happen to need it later." The user should not have
to name-check a skill that's obviously in scope; that's what the
trigger lines are for.

Re-do this check at the top of each commit's Implement step — a
later commit may bring different files or a different domain into
scope.

## Parsing the Commits section

Find the line `## Commits` and read the numbered list that follows,
until the next `## ` heading. Each commit entry has the shape:

```
1. **<title>** — <description>.
   *Verify:* <how to verify>.
```

A commit is **complete** if its number is followed by `✅` (e.g.,
`1. ✅ **<title>** — ...`). A commit is **next** if it is the first
non-✅ entry in order.

If the format is loose (the drafter used different punctuation, no
*Verify:* line, etc.), be liberal — extract title and description as
best you can, and ask the user about verify if it's missing.

## The per-commit loop

For each commit, in order:

### Announce

Print:

```
Commit N of M: <title>
  Description: <description>
  Verify:      <verify line>
```

If this is a resumed session (some commits already ✅), also note
which earlier commits were skipped/done so the user has context.

### Implement

First, re-check the skills list (see *Match relevant skills first*) —
this commit may pull in a domain the previous one didn't. Invoke any
newly-relevant skill before editing code.

Then do the work, using whatever tools fit alongside the active
skill's guidance — `Edit`, `Write`, subagents for exploration, etc.

If implementation reveals the commit is wrong-shaped (too big, too
small, depends on something the plan didn't anticipate), **stop and
discuss with the user**. The plan is mutable; edit `CURRENT_PLAN.md`
to split, merge, or reorder commits, then resume.

### Verify

Run the *Verify:* step literally if it's a command (`make test`,
`./bin/foo --check`). If it's a manual check ("rendered output
identical"), do it explicitly and report what you observed.

If verification fails:
- **Don't propose a commit.** Diagnose, fix, re-verify.
- If the failure is a real design problem (not a typo), pause and
  loop in the user. Don't dig a deeper hole.

### Update the plan entry

Before showing the diff, edit the plan file's entry for this commit:

- If non-trivial decisions were resolved during implementation,
  append a `**Decisions:**` block with short bullets capturing each
  resolution. The shape is:

  ```
  1. ✅ **Title** — description.
     *Verify:* how to verify.
     **Decisions:**
     - <decision>: <resolution>.
     - <decision>: <resolution>.
  ```

  Bullets are short — context for each decision is already in the
  commit's other diff hunks; the plan entry just records the
  resolution so future readers don't have to reconstruct it from
  `git log -p`.

- If the commit was specced clearly enough that implementation was
  mechanical (no decisions to record), omit the `**Decisions:**`
  block — the bare `✅` is the whole record.

- Always mark the entry `✅`.

The plan edit gets staged alongside the code changes; the assertion
that every commit on a branch touches the plan file is what
`ramfjord:merge-worktree`'s preflight relies on to detect
contract-skipping.

### Show diff and propose commit message

Run `git status` and `git diff` (and `git diff --cached` if anything
is staged). Surface the changes for review — code edits and the plan
edit together.

Propose a commit message:
- Match the repo's existing style (check `git log --oneline -10` if
  unsure). Subject line ≤ ~70 chars. Body if there's anything
  non-obvious about the *why*.
- Include the standard footer per the harness's git instructions
  (the `Co-Authored-By:` line).

Present the proposed message. Then **wait for user approval**.

### Commit on approval

Stage what should be committed: the code changes **and** the plan
file edit (the `✅` mark plus any `**Decisions:**` block). Be specific
— don't `git add -A` if there are unrelated files. Use a HEREDOC for
the message:

```bash
git commit -m "$(cat <<'EOF'
<subject>

<body, if any>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

The commit message focuses on the code change; it doesn't restate
the decisions, since those live in the staged plan diff right next
to the code that motivated them.

If a pre-commit hook fails: investigate the failure, fix the underlying
issue, re-stage, **commit fresh** (do not `--amend`, the failed commit
didn't happen). Never `--no-verify`.

### Continue

Move on to the next commit unless:
- The user wants to pause/stop.
- All commits are now ✅ (see *Completion* below).

Between commits, do not start the next one without a brief beat — the
user may want to redirect.

## Resuming

If invoked on a plan that already has some `✅` commits, start at the
first un-checked one. Briefly summarize where you're picking up:

```
Resuming plan: 3 of 5 commits done (✅ 1, ✅ 2, ✅ 3).
Next: Commit 4 of 5: <title>
```

Don't re-run earlier verifies or re-show their diffs.

## When the plan needs editing

The plan is mutable. Edit the plan file (e.g., `plans/<slug>.md`)
directly when:

- A commit turns out to be two commits — split it, renumber.
- A commit is no longer needed — remove it (or mark it `✅` with a
  note explaining why no diff was needed).
- Something unexpected requires a new commit — insert it at the right
  spot.

Always check with the user before editing the plan structure. Trivial
notes (adding a "saw this gotcha" line in passing) don't need
permission.

## Completion

When all commits are `✅`:

1. Confirm with the user: anything else for this branch?
2. Suggest reasonable next steps:
   - Run `ramfjord:merge-worktree` to merge back to main and tear
     down the worktree.
   - Push the branch and open a PR (if a PR-based workflow is wanted
     instead of direct merge).
   - Run `ramfjord:merge-order` to enqueue if not merging immediately.
   - Draft a follow-up plan (often the `Future plans` section of the
     current plan has candidates).
3. Don't push, open a PR, or merge automatically — those are
   user-gated.

The `✅` marks reach `main` via the merge — no need to manually
re-mark the durable plan after merging.

## What this skill does NOT do

- Draft plans. That's `ramfjord:draft-plan`.
- Auto-commit. Every commit is gated on explicit user approval of
  the diff + message.
- `--amend`, force-push, or any destructive git operation.
- Skip pre-commit hooks.
- Open PRs, push, or merge. User-gated.
- Run in parallel across commits. Strictly serial — one at a time,
  approval between each.
