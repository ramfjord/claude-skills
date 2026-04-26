# Skills improvements (April 2026)

## Goal

Address three pain points across the ramfjord skills: (1) per-worktree swank isolation isn't reliably unique, (2) the lack of a real finish-task skill that closes out a worktree cleanly and folds learnings back into the durable plan, and (3) absence of a global pushback / gap-finding default.

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

### 2. Finish-task skill (`ramfjord-finish-task`)

Replace the TBD note in `ramfjord-start-task/SKILL.md` with a real skill that closes out a worktree.

**Open questions (to discuss before drafting):**
- Default merge strategy: ask each time, or set a default (ff-only / no-ff / squash)?
- Plan-update step: mandatory or skippable when nothing notable changed during execution?
- Auto-invoke when `do-plan` reports all commits done, or always user-invoked?
- Plan-update commit on main *before* merge (clean history) or as part of the merge?

**Agreed scope:**
- Run from main checkout only (refuse if cwd is the worktree being finished).
- Verify branch clean and all `## Commits` are `✅`.
- Diff worktree's `CURRENT_PLAN.md` against `plans/<slug>.md`, surface decisions/notes for folding into the durable plan, commit that update on main.
- Merge the branch.
- Tear down: `tmux kill-session` for the worktree's swank, `git worktree remove`, delete branch.
- Does **not** touch `MERGE_ORDER.md`.
- Does **not** push.

### 3. Swank per-worktree isolation + eval

Make tmux session names path-unique so collisions can't cause silent reuse, and add an eval that exercises the isolation guarantee.

**Agreed scope:**
- Session name becomes `<basename>-<8-char hash of absolute path>` (or similar). Store in `.swank-session` so the skill always reads the current worktree's session name rather than guessing from basename.
- Eval against `fixtures/elp/`: bootstrap main + two worktrees, assert 3 distinct sessions / ports / PIDs / state isolation. Bonus: a 4th throwaway repo also basenamed `elp` to prove cross-project safety.
- No artificial cap on session count.

## Commits

To be drafted per topic when we start it. Topic 1 needed no commits in the skills repo (the change was outside it).

## Future plans

Likely follow-ups once these land:
- Revisit `ramfjord-merge-order` — once finish-task exists, the queue file's role is even narrower; may be worth simplifying.
- Add comprehension-signal heuristics into specific skills if the global rule isn't enough on its own.

## Non-goals

- Not changing how `ramfjord-do-plan` walks commits.
- Not changing the plans/CURRENT_PLAN.md split (durable design doc vs. mutable working copy).
- Not committing `~/.claude/CLAUDE.md` to this repo — it's outside the skills directory by design.
