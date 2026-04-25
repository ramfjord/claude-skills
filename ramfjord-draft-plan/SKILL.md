---
name: ramfjord-draft-plan
description: Draft or edit a project plan as a markdown file under ./plans/. Reads sibling plans first to spot sequencing dependencies and shared work, so a new plan can defer or piggyback on what's already drafted instead of duplicating effort. Use when the user says "draft a plan", "let's plan X", "write a plan for Y", or refers to "the plan" / "a plan" in this repo.
---

# ramfjord-draft-plan

Plans live in `./plans/<slug>.md` at the repo root. They are committed, human-edited markdown — the durable artifact for "here's how we intend to approach X." Distinct from `CURRENT_PLAN.md` (per-worktree, gitignored, working notes) seeded by `ramfjord-start-task`.

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

Freeform markdown. Don't impose a rigid template — match the style of existing plans in the repo if there is one. A reasonable default skeleton when starting from scratch:

```markdown
# <topic>

## Goal

<one or two lines — what does "done" look like?>

## Context

<why now, what prompted this>

## Related plans

<bulleted list of sibling plans this depends on, overlaps with, or conflicts with — empty is fine, but the section should exist so future drafters know it was considered>

## Approach

<the actual plan — steps, alternatives considered, open questions>
```

The **Related plans** section is the load-bearing one for this skill. Even "none — checked `./plans/` on <date>" is a useful entry, because the next drafter knows the cross-check happened.

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
