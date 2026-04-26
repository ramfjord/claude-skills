---
name: ramfjord-draft-plan
description: Draft or edit a project plan as a markdown file under ./plans/. Reads sibling plans first to spot sequencing dependencies and shared work, so a new plan can defer or piggyback on what's already drafted instead of duplicating effort. Use when the user says "draft a plan", "let's plan X", "write a plan for Y", or refers to "the plan" / "a plan" in this repo.
---

# ramfjord-draft-plan

Plans live in `./plans/<slug>.md` at the repo root. They are committed, human-edited markdown — the durable artifact for "here's how we intend to approach X."

A plan covers **exactly one branch's worth of work** — what will land as a single feature branch, structured as an ordered series of commits. Work that is genuinely "later, separate scope" goes in a `Future plans` section (one-liners), not as additional sections of this plan; draft those as their own plans when ready.

`ramfjord-start-task` later carries the chosen plan into a worktree (writing a small `CURRENT_PLAN.md` marker file that points back at `plans/<slug>.md`); `ramfjord-do-plan` walks the `Commits` list one item at a time, editing the plan as it goes.

Plans are *living* documents. `ramfjord-do-plan` appends a `**Decisions:**` block to each commit's entry as decisions get resolved during implementation, and stages those edits alongside the code in the same commit. So when drafting, your job is to verify the proposed approach is feasible and size each commit into something reviewable — but you don't need to nail every implementation detail. Ambiguities that surface during the commit get resolved at execution time and recorded in the plan via `do-plan`'s decisions appends. Over-specifying upfront just creates churn when execution refines it.

## What this skill does

1. Locate / create `./plans/`.
2. Read every existing `./plans/*.md` before drafting (see *Cross-plan reading* below — this is the point of the skill).
3. Draft or edit the target plan, explicitly noting sequencing and synergy with sibling plans.
4. Save as `./plans/<slug>.md`. Do not auto-commit.

## Inputs

- **Topic** — required. What the plan is about.
- **Slug** — optional. Otherwise derive: kebab-case, 3–5 words. Match the style of existing files in `./plans/` if a convention is visible there.

## Preflight

```bash
git rev-parse --show-toplevel   # run from a repo
ls plans/ 2>/dev/null            # see what's there
```

If `./plans/` doesn't exist, create it. If `./plans/` isn't tracked or referenced anywhere, mention to the user that this skill assumes plans are committed; don't silently `git add`.

If a plan with the same slug already exists, default to *editing* it rather than overwriting. Confirm with the user if intent is ambiguous.

## Cross-plan reading (the important part)

Before writing a single line of the new plan, read **every** other file in `./plans/`. Skim, don't memorize — you're looking for three things:

1. **Sequencing** — does another plan need to land first? If plan A introduces a module that plan B builds on, plan B should say "blocked on A" rather than re-deriving A's design. If A is in flight, B's near-term steps may be no-ops worth deferring.
2. **Synergy** — is another plan already going to do part of this work? If plan A is refactoring the config loader and the new plan also needs config changes, fold the new plan's config work into A's scope (or note it as a dependency) instead of duplicating.
3. **Conflict** — does another plan move in a direction that contradicts this one? Surface it; don't paper over it. The user decides which plan wins.

Cite sibling plans by filename when they're relevant. A reader of one plan should be able to discover related plans from inside it.

**Avoid work by waiting.** If the cleanest version of this plan is "do nothing until plan X ships, then revisit," say that. A short plan that defers is better than a long plan that duplicates.

## Drafting

Match the style of existing plans in the repo if there is one. Default skeleton when starting from scratch:

```markdown
# <topic>

## Goal

<one or two lines — what does "done" look like for this branch?>

## Context

<why now, what prompted this>

## Related plans

<bulleted list of sibling plans this depends on, overlaps with, or conflicts with — empty is fine, but the section should exist so future drafters know it was considered>

## Design notes

<optional — shared rationale referenced by multiple commits below, so each commit's description can stay short. Skip if there's no cross-cutting design context>

## Commits

Ordered list of atomic, reviewable commits. Each must leave the tree green (tests pass, build works) on its own. Format:

1. **<title>** — <one-line what + why>.
   *Verify:* <how we know it works — tests added, manual check, command output>.
2. ...

## Future plans

<optional — one-line entries for follow-up work that is out of scope for this branch but worth remembering. Each should become its own plan when ready. Omit the section if there's nothing>

## Non-goals

<optional — things this plan deliberately does not do, to head off scope creep>
```

Two sections are load-bearing for this skill:

- **Related plans** — even "none — checked `./plans/` on <date>" is a useful entry, because the next drafter knows the cross-check happened.
- **Commits** — `ramfjord-do-plan` parses this section. Without it the plan can be read by humans but not walked by the do-plan skill.

### Sizing commits

The drafter is responsible for sizing. Heuristics:

- Each commit should be a single coherent diff a reviewer can read in one sitting (rough rule: under ~250 changed lines).
- Each commit must leave tests green. If a refactor *necessarily* breaks tests mid-way, either it's actually two commits (introduce alongside, then switch over) or the test changes belong in the same commit as the code changes.
- Pure refactors first (no behavior change), then additions, then wiring. This makes each commit trivially safe to review.
- If a commit ends up with several unrelated *Verify:* lines, it's probably two commits.
- Don't fragment for its own sake. Two-line commits are noise.

Five to seven commits is a typical size for a focused branch. More than ten and the plan is probably trying to do too much in one branch — split it.

## Editing an existing plan

Same cross-plan reading step applies — sibling plans may have shifted since this one was last touched. If editing reveals that the plan should now defer to or merge with another, propose that to the user rather than just patching in place.

## Hand off

Tell the user:
- Path to the file written/edited.
- Any sibling plans worth their attention (sequencing or synergy hits).
- Anything you deferred or folded elsewhere, and why.

## What this skill does NOT do

- Execute the plan. Use `ramfjord-start-task` when ready to begin work.
- Commit the file. The user reviews and commits.
- Track plan status (done / abandoned / superseded). That's a separate concern; if it comes up, suggest a convention rather than inventing one here.
