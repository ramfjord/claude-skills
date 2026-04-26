# Living plans + merge-worktree (April 2026)

## Goal

Shift the plan-driven workflow so that `plans/<slug>.md` is a *living*
document that grows during execution — decisions made while implementing
each commit get appended to that commit's entry in the plan and committed
alongside the code change. Then close the loop with `ramfjord-merge-worktree`,
the long-deferred skill that merges a finished worktree's branch back to
main and tears down its scaffolding.

## Context

Conversation 2026-04-26, immediately after `skills-improvements.md`'s
Topic 3 (swank isolation) landed. Topic 2 of that plan (merge-worktree)
was deferred pending open questions; while resolving those, we noticed
the deeper issue is that the plan↔execution split is lossy — decisions
made during implementation never reach the durable plan unless someone
remembers to fold them in by hand at merge time. The fix is to stop
treating `plans/<slug>.md` as a frozen design doc and start treating it
as the running record of the work, edited inline by `ramfjord-do-plan`
as each commit lands.

That reshapes Topic 2 (`merge-worktree` no longer needs a plan-update
step) and adds three smaller adjustments to peer skills (`do-plan`,
`start-task`, `draft-plan`).

## Related plans

- `skills-improvements.md` — Topic 2 there is superseded by this plan.
  Topics 1 and 3 there are already complete and unaffected. A note
  pointing here will be added to that file's Topic 2 section as part
  of this plan's first commit.

## The conceptual shift

**Before:** `start-task` copies `plans/<slug>.md` → `CURRENT_PLAN.md`
in the worktree. `do-plan` walks `CURRENT_PLAN.md`, marks `✅` there
(gitignored, never committed). `plans/<slug>.md` stays frozen on the
branch. Decisions made during execution live only in commit messages
and conversation history — recovering them later means archaeology.

**After:** `start-task` writes a tiny marker stub at `CURRENT_PLAN.md`
(just `Branch:` + `Plan source:` lines) so the worktree is
self-describing, but doesn't copy the plan content. `do-plan` walks
`plans/<slug>.md` directly, edits it as work progresses (mark `✅`,
append a `**Decisions:**` sub-block when something non-trivial was
resolved), and stages the plan edit alongside the code in each
commit. By the time the branch reaches `merge-worktree`, the plan in
the branch already reflects what actually happened. `merge-worktree`
just merges + tears down; no plan-update logic.

**Why squash is now obviously wrong:** each commit's diff carries its
own decision record. Squashing N commits collapses N decision entries
into one undifferentiated blob. `merge-worktree` will refuse `--squash`.

## Decision-capture format

Each commit entry in a plan's `## Commits` section is shaped:

```
1. **Title** — one-line description.
   *Verify:* how to verify it.
```

After `do-plan` finishes the commit, it edits the entry in place to:

```
1. ✅ **Title** — one-line description.
   *Verify:* how to verify it.
   **Decisions:**
   - <decision>: <resolution>.
   - <decision>: <resolution>.
```

If no decisions were made (the commit was specced clearly enough that
implementation was mechanical), the `**Decisions:**` block is omitted —
the bare `✅` is the whole record.

The decisions block is short bullets, not prose. Context for each
decision is already in the commit's other diff hunks; the plan entry
just needs the resolution recorded so future readers don't have to
reconstruct it from `git log -p`.

## Agreed scope

### `ramfjord-do-plan` changes

- Treat the plan path argument as `plans/<slug>.md` directly (no longer
  `CURRENT_PLAN.md`). The worktree's `CURRENT_PLAN.md` is just a
  marker stub `do-plan` doesn't read.
- After each commit's verify step, before staging: if non-trivial
  decisions were resolved during implementation, append a
  `**Decisions:**` block to that commit's entry in the plan file.
- Mark the entry `✅` in the plan file.
- Stage the plan file alongside the code changes; commit them together.
- The commit message focuses on the code change; it doesn't restate
  the decisions (those live in the staged plan diff).

### `ramfjord-start-task` changes

- Drop the `cp plans/<slug>.md ./worktrees/<branch>/CURRENT_PLAN.md`
  step.
- In its place, write a 2-line marker stub at
  `./worktrees/<branch>/CURRENT_PLAN.md`:

  ```
  Branch: <branch>
  Plan source: ./plans/<slug>.md
  ```

- Update the launch command printed at hand-off to point `do-plan` at
  the durable plan (which is in the branch's working tree via the
  normal checkout):

  ```
  (cd ./worktrees/<branch> && claude "/ramfjord-do-plan plans/<slug>.md")
  ```

- Replace the `Separate finish-task skill (TBD)` line in the
  *What this skill does NOT do* section with a pointer to
  `ramfjord-merge-worktree`.

### `ramfjord-draft-plan` changes

- Add a short note that plans evolve during execution: each commit's
  body should specify enough that the *approach is verified possible*
  at plan time, but doesn't need to nail every implementation detail —
  ambiguities are expected to be resolved during the commit, with the
  resolution captured in the plan via `do-plan`'s `**Decisions:**`
  appends.

### `ramfjord-merge-worktree` (new skill)

- Run from main checkout only. Refuse if cwd is the worktree itself.
- Identify the target worktree:
  - Infer from conversation history when possible (the user's recent
    work in this session usually names exactly one worktree).
  - Confirm with the user before merging unless one obvious worktree
    exists with all commits `✅` and no other plausible candidate.
- Preflight checks:
  - Branch clean (no uncommitted changes in the worktree).
  - Plan has exactly one `## Commits` section. If multiple, error out
    with a clear message — multi-topic plans are not supported by this
    skill (split into per-topic plans before using).
  - All entries in that `## Commits` section are `✅`.
  - Every commit on `main..<branch>` touches the plan file. (If a
    commit edited code without updating the plan, surface it and stop —
    that's a sign `do-plan`'s contract was bypassed and decisions may
    be missing.)
- Merge: `git merge --ff` (fast-forward when possible, merge commit
  when not). Refuse `--squash` always with a comment about why.
- Teardown:
  - Invoke `ramfjord-swank-image`'s `cleanup-swank.sh "$WORKTREE"`.
  - `git worktree remove ./worktrees/<branch>`.
  - `git branch -d <branch>`.
- Does **not** push. Does **not** touch `MERGE_ORDER.md`.

### Removal of redundant convention

The "manually mark commits ✅ on main" pattern (e.g., commit `fd2f513
Mark Topic 3 commits complete in plan`) becomes obsolete — the marks
arrive via the merge. No documentation currently codifies the old
pattern, so removal is just a matter of not doing it going forward.
Worth a one-line note in `do-plan/SKILL.md` so future-Claude doesn't
re-invent it.

## Open questions

None — resolved before drafting:
- **Decision-capture format:** `**Decisions:**` sub-block per commit
  entry, short bullets, omitted when no decisions were made.
- **Mechanical commits:** `do-plan` still touches the plan file (just
  the `✅` mark) so every commit on the branch has plan + code
  together — keeps the preflight invariant simple.
- **`draft-plan` adjustment:** initial drafts verify approach is
  possible but leave implementation ambiguity for execution time.
- **`CURRENT_PLAN.md` shape:** stays as a gitignored marker stub
  identifying the worktree's plan, not a copy of the plan content.
- **Test placement:** extend the existing `test-isolation.sh` with a
  small merge-worktree teardown assertion at the end (the punt from
  `skills-improvements.md` Topic 3). The swank-side test scaffolding
  is already in place; no new test script needed.

## Commits

**Estimate:** ~310 LoC across 5 commits, touching 5 skill directories.
One subsystem (the skills repo).

1. ✅ **Update `ramfjord-do-plan` for inline plan updates** (~50 LoC)
   - `SKILL.md`: per-commit loop now reads `plans/<slug>.md`, appends
     `**Decisions:**` sub-block when non-trivial decisions were made,
     marks `✅`, stages plan file with code, commits them together.
   - Document the decision-capture format with a small example.
   - Note that the old "mark ✅ on main after merge" pattern is obsolete.
   - Update *Inputs* default from `./CURRENT_PLAN.md` to a path under
     `plans/`.
   - Add a one-line pointer in `skills-improvements.md`'s Topic 2
     section noting it's superseded by this plan.
   - *Verify:* read-through of the SKILL — describes the new behavior
     without internal contradictions; example renders right.

2. **Update `ramfjord-start-task` to write marker stub** (~30 LoC)
   - `SKILL.md`: drop the `cp` step from *Copy the plan into the
     worktree*; rename that section to *Write the worktree marker*.
   - Stub content: `Branch:` + `Plan source:` lines only.
   - Update the printed launch command to point at `plans/<slug>.md`.
   - Replace the `finish-task skill (TBD)` line with a pointer to
     `ramfjord-merge-worktree`.
   - *Verify:* run `start-task` against a real plan in this repo,
     check the stub is written, the launch command points at the
     right path, and `plans/<slug>.md` is unchanged on disk.

3. **Update `ramfjord-draft-plan` to note plan evolution** (~10 LoC)
   - `SKILL.md`: short note (1 paragraph) that plans grow during
     execution via `do-plan`'s `**Decisions:**` appends, so initial
     drafts should verify approach feasibility but not over-specify
     implementation details.
   - *Verify:* read-through; new note doesn't conflict with existing
     guidance about commit-sizing.

4. **Add `ramfjord-merge-worktree` skill** (~200 LoC)
   - New `ramfjord-merge-worktree/SKILL.md` covering: inputs (worktree
     inference + confirmation), preflight (cwd, branch clean, single
     `## Commits` section, all `✅`, plan-coverage check), merge
     (`--ff`, refuse `--squash`), teardown (cleanup-swank, worktree
     remove, branch delete), what-this-skill-does-NOT-do.
   - New `ramfjord-merge-worktree/check-plan-coverage.sh` (~30 LoC)
     — walks `main..<branch>` and asserts every commit's diff includes
     the plan file. Output: pass, or list of offending commits.
   - *Verify:* manual smoke run of `check-plan-coverage.sh` against
     a real branch in this repo (the branch this plan is implemented
     on, by the time this commit lands).

5. **Extend `test-isolation.sh` with merge-worktree teardown check** (~30 LoC)
   - At the end of `ramfjord-swank-image/test-isolation.sh` (after
     the existing 4-image isolation assertions), invoke the scripted
     teardown sequence used by `merge-worktree` against one of the
     worktrees: `cleanup-swank.sh "$WORKTREE"` →
     `git worktree remove` → `git branch -d`. (The full skill is
     Claude-driven; this commit exercises the mechanical hand-off.)
   - Assert: tmux session gone, `.swank-session` / `.swank-port` /
     `.mcp.json` gone, worktree dir gone, branch absent from
     `git branch --list`.
   - The existing trap already handles cleanup of the *other* three
     worktrees; just make sure the trap is idempotent against the
     one we tore down explicitly.
   - *Verify:* `./ramfjord-swank-image/test-isolation.sh` exits 0.

**Sequencing:** C1 first (do-plan's new behavior is the linchpin —
once it's documented, everything else can reference it). C2 and C3
are independent and could be reordered, but C2 before C3 since it's
the larger change. C4 depends conceptually on C1 (its preflight
assumes do-plan's contract). C5 depends on C4 (tests the skill C4
adds). This plan itself is the first end-to-end exercise of the new
flow — `do-plan` will append `**Decisions:**` blocks here as the work
goes.

## Future plans

- Revisit `ramfjord-merge-order` once `merge-worktree` exists — the
  queue file's role is even narrower; may be worth simplifying.
- Consolidate `.swank-port` + `.swank-session` (+ generated `.mcp.json`)
  into a single `.swank` source-of-truth file. (Already noted in
  `skills-improvements.md`.)
- Heavy eval of `do-plan` itself (fixture plan + scripted Claude
  session via SDK, asserting per-commit plan/code colocation).
  Skipped here in favor of the lightweight `check-plan-coverage.sh`
  preflight, which catches the same regression at merge time. Revisit
  only if the preflight proves insufficient.
- Un-gitignore `fixtures/elp` so the test fixture is reproducible
  without re-cloning.

## Non-goals

- Not changing `ramfjord-do-plan`'s commit-walking shape (still serial,
  still gated on user approval per commit).
- Not auto-invoking `merge-worktree` from `do-plan`'s completion step —
  it stays user-invoked across the worktree → main process boundary.
- Not pushing or PR-opening from `merge-worktree`.
- Not touching `MERGE_ORDER.md` from `merge-worktree`.
- Not supporting multi-topic plans in `merge-worktree` — error out
  with a clear message, revisit if it actually comes up.
