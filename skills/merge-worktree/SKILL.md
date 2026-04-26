---
name: merge-worktree
description: Close out a finished worktree — verify the branch is ready, merge it back to main with --ff, and tear down the worktree (swank image, worktree dir, branch). Use when the user says "merge the worktree", "finish task", "close out X", "wrap up the branch", or after `ramfjord:do-plan` reports all commits done.
---

# ramfjord:merge-worktree

End-of-task counterpart to `ramfjord:start-task`. Takes a worktree
whose plan is fully implemented, sanity-checks the branch, merges it
back to `main`, and tears down the scaffolding so nothing is left
hanging around.

This skill is mostly preflight — by the time `merge-worktree` runs,
`ramfjord:do-plan` has already done the per-commit work of recording
decisions in the plan file and committing them alongside the code.
The plan on the branch already reflects what happened; the merge
just delivers it to `main`.

## Inputs

- **Worktree** — required, but inferable. Either the branch name,
  the worktree path (`./worktrees/<branch>`), or the plan slug.
  - **Inference from conversation**: if the user has been working in
    one worktree this session, default to that. If exactly one
    `./worktrees/*` exists with all-`✅` commits in its plan and no
    other plausible candidate, default to that.
  - **Confirm before merging** unless the inference is unambiguous
    (one obvious worktree, recently-active in this session). When in
    doubt, list candidates and ask.

## Preflight

Run from the main checkout. Refuse if cwd is the worktree being
finished — the merge needs `main`'s working tree, and removing a
worktree you're standing in is a footgun.

```bash
git rev-parse --show-toplevel        # main checkout root
git rev-parse --abbrev-ref HEAD      # should be 'main'
test ! -L "$PWD" && \
  test "$PWD" != "<main-toplevel>/worktrees/<branch>"   # not in target worktree
```

Then walk these checks in order, stopping on the first failure:

1. **Branch exists, worktree exists.** `git worktree list` should
   show `./worktrees/<branch>`.

2. **Branch is clean.** No uncommitted changes in the worktree
   (`git -C ./worktrees/<branch> status --porcelain` is empty).

3. **Plan has exactly one `## Commits` section.** Multi-topic plans
   are not supported by this skill — error out with a clear message
   telling the user to split into per-topic plan files. (Future
   work: support per-topic merges if this comes up.)

4. **All entries in `## Commits` are `✅`.** If any are unchecked,
   the branch isn't done. Tell the user which.

5. **Every commit on `main..<branch>` touches the plan file.** Run:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/merge-worktree/check-plan-coverage.sh \
     <branch> plans/<slug>.md
   ```

   This script lists any commits whose diff doesn't include the
   plan file. If any are listed, surface them and stop — that's a
   sign `do-plan`'s contract was bypassed (hand-edit, manual
   `git commit` outside the do-plan loop), and decisions for those
   commits may be missing from the plan. Resolve manually:
   either amend the commit to include the plan update, or
   acknowledge there were no decisions to record and add a trivial
   plan touch (e.g., a no-op whitespace tweak with the ✅ mark) to
   the offending commit.

## Confirm and merge

Show the user:
- Branch name and worktree path.
- Commit count being merged (`git rev-list --count main..<branch>`).
- Recent commit subjects (`git log --oneline main..<branch>`).
- The plan file's path on `main` (will receive the merged updates).

Wait for confirmation. Then:

```bash
git merge --ff <branch>
```

`--ff` fast-forwards when possible and creates a merge commit when
not. **Never `--squash`** — `do-plan` deliberately recorded decisions
per-commit; squashing would collapse N decision records into one
undifferentiated blob. If the user asks for squash, decline and
explain.

If the merge fails (conflict), stop. Tell the user. The teardown
step does not run on a failed merge.

## Teardown

Once the merge succeeds:

```bash
# 1. Clean up the swank image (if any)
${CLAUDE_PLUGIN_ROOT}/skills/swank-image/cleanup-swank.sh \
  ./worktrees/<branch>

# 2. Remove the worktree
git worktree remove ./worktrees/<branch>

# 3. Delete the branch (now merged)
git branch -d <branch>
```

`cleanup-swank.sh` is idempotent — if there was no swank image (e.g.,
non-Lisp project), it reports that and exits 0. Don't condition the
call on whether a Lisp project; the script handles the no-op case.

`git worktree remove` will refuse if the worktree has untracked or
modified files — preflight already checked clean, so this should
succeed. If it fails, surface the error and let the user resolve.

`git branch -d` (lowercase) only deletes if the branch is merged.
That's the safety we want — if for some reason the branch isn't
merged (shouldn't happen given preflight passed and merge succeeded),
fail loud.

## Report

After teardown, print a short summary:

```
Merged <branch> → main (N commits).
Cleaned up: <worktree path>, <swank session> (if any), branch.
Plan file plans/<slug>.md is now updated on main.
```

Suggest next steps if obvious from the plan's *Future plans* section
(those are candidates for the next `ramfjord:draft-plan` invocation).

## What this skill does NOT do

- **Push.** `merge-worktree` keeps everything local. Push manually
  when you want it on the remote.
- **Open PRs.** This skill is for direct-to-main workflows. If the
  project is PR-based, push the branch and open the PR instead of
  invoking this skill.
- **Touch `MERGE_ORDER.md`.** Queue management is `ramfjord:merge-order`.
  If the merged branch was queued, remove its entry there separately.
- **Force-push, `--amend`, or any destructive history rewrite.**
- **Auto-trigger from `do-plan`.** `do-plan` runs in the worktree's
  Claude session; this skill must run from `main`. Crossing that
  process boundary is a useful pause point for the user, not a
  problem to engineer around.
- **Squash merge.** See above. Decisions per-commit are load-bearing.
- **Run for multi-topic plans.** Error out with a clear message;
  split the plan first.
