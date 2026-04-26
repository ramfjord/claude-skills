# Skills improvements (April 2026)

## Goal

Address three pain points across the ramfjord skills: (1) per-worktree swank isolation isn't reliably unique, (2) the lack of a real merge-worktree skill that closes out a worktree cleanly and folds learnings back into the durable plan, and (3) absence of a global pushback / gap-finding default.

## Context

User feedback session 2026-04-26. Each topic is roughly its own branch's worth of work, but they're being tracked together because the user wants to walk through them sequentially in one collaboration.

## Related plans

None — `./plans/` was empty before this file. Cross-check performed 2026-04-26.

## Topics

### 1. ✅ Global pushback / gap-finding defaults

Make pushback, gap-finding, motivation probing, and scale estimation default behavior across every Claude Code session.

**Resolutions (beyond the original ask):**

- **Location**: `~/.claude/CLAUDE.md` (user-global), not a skill. Skills load on invocation; the global CLAUDE.md auto-loads on every session, which matches "always on" better than any skill mechanism would.
- **Pushback framing**: causal effects, not binary right/wrong. "This has downside X because of its interaction with Y" — lay out the chain of effects so the user can verify the computation. Hedging on uncertain effects is fine; hedging to soften a confident disagreement is not.
- **Visibility**: pushback is always surfaced explicitly at both plan and implement time. The failure mode it fights: gaps that look minor at plan time become "ooooh that's the issue we've had all along" three commits in.
- **Scale estimates**: LoC + files touched + subsystems involved, given up front for non-trivial work. Estimate-overrun during implementation is itself a yellow flag — surface it, don't power through.
- **Comprehension signals**: synthesis from the user is strong evidence the point landed; generic acknowledgment is a soft signal it may not have. On load-bearing points, re-raise concretely. Direct framing ("do you understand X will impact Y?") is opted into.
- **Motivation probing**: before acting on a non-trivial request, check whether the implied *why* matches the model. State the motivation back as a verification line.
- **No sugarcoating**: confident disagreement gets voiced plainly.

**Verify:** `~/.claude/CLAUDE.md` exists with these rules. Test by starting a fresh Claude Code session in an unrelated project and observing whether pushback / motivation-probing behavior shows up without prompting.

### 2. Merge-worktree skill (`ramfjord-merge-worktree`)

Replace the TBD note in `ramfjord-start-task/SKILL.md` with a real skill that closes out a worktree by merging it back to main and tearing down its scaffolding.

**Naming**: `ramfjord-merge-worktree`. Considered `finish-task` (symmetry with `start-task`) but `merge-worktree` is more descriptive of the central act. Still changeable if it grates in practice.

**Cleanup coupling decision (2026-04-26)**: For v1, `merge-worktree` invokes `ramfjord-swank-image` directly with a cleanup directive — coupled, not via a marker-file registry. Rationale: only one cleanup-needing skill exists today (swank-image), and a registry pattern is premature for one consumer. The aspirational generalization (marker-file dispatch so workflow skills don't name lisp skills) is captured in `README.md` as a project value; revisit when a second cleanup case appears.

**Cleanup lives in `ramfjord-swank-image`, not a separate skill.** Lifecycle (setup, recovery, teardown) belongs in one place; splitting cleanup into its own skill would force every consumer of the image to know about two skills. `swank-image` grows a documented cleanup mode that takes a target directory, kills the tmux session, removes `.swank-session`, and reports.

**Open questions (still to resolve before drafting commits):**
- Default merge strategy: ask each time, or set a default (ff-only / no-ff / squash)?
- Plan-update step: mandatory or skippable when nothing notable changed during execution?
- Auto-invoke when `do-plan` reports all commits done, or always user-invoked?
- Plan-update commit on main *before* merge (clean history) or as part of the merge?

**Agreed scope:**
- Run from main checkout only (refuse if cwd is the worktree being finished).
- Verify branch clean and all `## Commits` are `✅`.
- Diff worktree's `CURRENT_PLAN.md` against `plans/<slug>.md`, surface decisions/notes for folding into the durable plan, commit that update on main.
- Merge the branch.
- Tear down: invoke `ramfjord-swank-image` cleanup (handles `tmux kill-session` and `.swank-session` removal internally), then `git worktree remove`, delete branch.
- Does **not** touch `MERGE_ORDER.md`.
- Does **not** push.

### 3. Swank per-worktree isolation + eval

Make tmux session names path-unique so collisions can't cause silent reuse, add a documented cleanup mode, and add an eval that exercises both the isolation guarantee and the cleanup hand-off from `merge-worktree`.

**Sequencing**: Topic 3 lands before Topic 2. The path-unique session naming and cleanup mode are prerequisites for `merge-worktree`'s teardown step and for the combined eval to be meaningful — otherwise the cleanup eval would be testing teardown of the buggy (collision-prone) version.

**Agreed scope:**
- Session name becomes `<basename>-<8-char hash of realpath of directory>`. Hash is `sha256(realpath) | head -c8` — realpath rather than raw `$PWD` so symlinked parents don't produce different sessions for the same logical worktree.
- Introduce `.swank-session` (gitignored) at the directory root, containing the session name. The skill always reads this file rather than re-deriving from `pwd`, so we can change the naming scheme later without orphaning live sessions.
- File-count decision: keep status quo + add `.swank-session` (three files: `.swank-port`, `.swank-session`, `.mcp.json`). Considered consolidating into one `.swank` file (port + session, with `.mcp.json` generated from it); deferred to a future plan to keep Topic 3 scoped.
- Add a cleanup mode to `ramfjord-swank-image`: given a target directory, read its `.swank-session`, `tmux kill-session` it, remove `.swank-session`/`.swank-port`/`.mcp.json`, report what was torn down (or that nothing was there).
- **Migration of existing worktrees**: accept manual cleanup of orphan basename-only sessions on first rollout. The skill's bootstrap will refuse to start over an existing session of the *new* name, but won't see old basename-only sessions as conflicts. Acceptable cost given current worktree count is small.
- **Eval scripts** (factored, not one big script):
  - `assert-swank-healthy.sh DIR` — bootstrap + per-dir assertions (port LISTEN, session exists, files written, eval reachable). Reusable.
  - `test.sh` — calls `assert-swank-healthy.sh fixtures/elp` once. Existing single-dir smoke test, simplified to use the helper.
  - `test-isolation.sh` — creates two `git worktree`s under `fixtures/elp/worktrees/` plus a `cp -r fixtures/elp /tmp/elp-collision-$$` for the cross-project basename-collision case, calls `assert-swank-healthy.sh` on all 4, then asserts: 4 distinct session names, 4 distinct ports, and state isolation (set a `*eval-marker*` defparameter in one image, assert unbound in another). Cleans up all 4 sessions + worktrees + temp dir on exit.
- The cross-project basename-collision case is **a core assertion**, not a bonus — it's the failure mode this whole topic exists to fix.
- After Topic 2 lands, extend `test-isolation.sh`: invoke `merge-worktree` on one of the worktrees, assert tmux session gone, `.swank-session` gone, worktree removed, branch deleted.
- No artificial cap on session count.

**Known limitation (not fixed here):** Bootstrap port allocation walks up from 4005 picking the first free port. Two `bootstrap-swank.sh` invocations racing in parallel can collide on the same port. The eval sidesteps this by bootstrapping sequentially. Possible follow-up: switch to "pick a random port in 4005–4999, retry on conflict" — probably not worth doing unless concurrent bootstraps actually become a real workflow.

**Shared tmux/swank-info skill — not in scope.** Considered factoring common knowledge (session naming, file location) into a shared skill that both `swank-image` and `merge-worktree` could read. Rejected for v1: cleanup lives in `swank-image`, so `merge-worktree` never needs to know swank internals. Revisit only if a third consumer appears.

## Commits

Topic 1 needed no commits in the skills repo (the change was outside it).
Topic 2 commits to be drafted once its open questions are resolved.

### Topic 3 commits

**Estimate**: ~200 LoC across 6–8 files in `ramfjord-swank-image/`. One subsystem.

1. ✅ **Hash-based session naming + `.swank-session`** (~50 LoC)
   - `bootstrap-swank.sh`: derive session name as `<basename>-<sha256(realpath)|head -c8>`, write to `.swank-session`.
   - `SKILL.md`: update Conventions section and the "Quick checks" bash snippet (currently `SESSION_NAME=$(basename "$PWD")` → read from `.swank-session`).
   - `test.sh`: update session-name assertion to match (will be replaced wholesale in commit 2).
   - `.swank-session` is in user's global gitignore — no per-repo gitignore change needed.

2. ✅ **Extract `assert-swank-healthy.sh` helper, slim `test.sh`** (~40 LoC moved)
   - New `assert-swank-healthy.sh DIR` with the per-dir assertions currently inline in `test.sh`.
   - `test.sh` becomes a thin wrapper: calls the helper on `fixtures/elp`, keeps its cleanup trap.
   - Pure refactor — both green at end of commit.

3. ✅ **Test recovery from stale `.swank-session`** (~20 LoC)
   - Extend `test.sh`: after the first happy-path assertion, `tmux kill-session` to simulate a host reboot, then run `assert-swank-healthy.sh` again and assert the same session name comes back live (proves bootstrap recovers when `.swank-session` outlives its tmux session).
   - **No production code change.** This works today because the realpath hash is deterministic — the test pins that property so a future hash-scheme change can't silently break recovery without us noticing.

4. ✅ **Add cleanup mode** (~60 LoC)
   - New `cleanup-swank.sh DIR` — reads `.swank-session`, `tmux kill-session`, removes `.swank-session` / `.swank-port` / `.mcp.json`, reports what was torn down (or that nothing was there). Idempotent.
   - `SKILL.md`: new "Cleanup" section documenting when this is invoked (today: manual; later: by `merge-worktree`).
   - Verify in commit body: bootstrap → cleanup → assert nothing left.

5. ✅ **Add `test-isolation.sh`** (~100 LoC)
   - Bootstrap 2 `git worktree`s under `fixtures/elp/worktrees/` + a `cp -r fixtures/elp /tmp/elp-collision-$$` for the cross-project basename collision case.
   - Call `assert-swank-healthy.sh` on all 4.
   - Assert: 4 distinct session names, 4 distinct ports, state isolation via `*eval-marker*` defparameter.
   - Cleanup trap: `cleanup-swank.sh` on all 4 + `git worktree remove` + `rm -rf` temp dir.

**Sequencing**: C1 first (everything assumes new naming). C2 before C3–C5 (helper exists for reuse). C3 (recovery test) is independent of C4/C5 but lives near C2 since both touch `test.sh`. C4 before C5 so test-isolation.sh's trap can use `cleanup-swank.sh` rather than ad-hoc tmux/rm.

## Future plans

Likely follow-ups once these land:
- Revisit `ramfjord-merge-order` — once merge-worktree exists, the queue file's role is even narrower; may be worth simplifying.
- Add comprehension-signal heuristics into specific skills if the global rule isn't enough on its own.
- Consolidate `.swank-port` + `.swank-session` (+ generated `.mcp.json`) into a single `.swank` source-of-truth file.
- Un-gitignore `fixtures/elp` so the test fixture is reproducible without re-cloning. (Currently CLAUDE.md instructs re-cloning if missing; checking it in would simplify that.)
- Random port allocation (pick in 4005–4999, retry on conflict) to make concurrent `bootstrap-swank.sh` calls safe — only worth doing if concurrent bootstraps become a real workflow.

## Non-goals

- Not changing how `ramfjord-do-plan` walks commits.
- Not changing the plans/CURRENT_PLAN.md split (durable design doc vs. mutable working copy).
- Not committing `~/.claude/CLAUDE.md` to this repo — it's outside the skills directory by design.
