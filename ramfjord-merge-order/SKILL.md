---
name: ramfjord-merge-order
description: Maintain ./plans/MERGE_ORDER.md, the agreed merge order for in-flight branches. Read, append, remove, or reorder entries. Use when starting/finishing work, when queue-jumping for a yak-shave, or when the user asks "what's the merge order" / "what merges next" / "move X before Y".
---

# ramfjord-merge-order

`./plans/MERGE_ORDER.md` is a coordination contract between agents working in different worktrees. It is the **only** authoritative source for the order in which active branches should merge into `main`. It does not influence base branches — every branch is cut from `main` and rebases only onto `main`.

## File location and visibility

The file lives at `./plans/MERGE_ORDER.md` on `main`. Worktrees should read main's copy, not their branch's stale copy:

```bash
git show main:plans/MERGE_ORDER.md
```

Edits happen on `main` only. From a worktree, `cd` to the main checkout (or perform the edit there). Each edit is a one-line commit on main; no work content rides with it.

## File format

```markdown
# Merge order

Active branches in intended merge order. Top merges first. Remove entries when their branch merges or is abandoned.

1. <branch-slug> — <one-line note, optional>
2. <branch-slug>
3. <branch-slug> — blocks on review from @someone
```

Numbered list. The number is decorative — position in the list is what matters; renumbering on insert/remove is fine and expected. Notes after `—` are optional and freeform (reviewer, blocker, why it's queued where it is).

If the file doesn't exist, create it with just the header and an empty list.

## Operations

### Read

```bash
git show main:plans/MERGE_ORDER.md
```

Or read the file directly when on main. Show the user the current order verbatim when asked.

### Append (start of work)

Default insertion is at the end. If the user specifies a position ("insert before `foo`", "at front", "after `bar`"), honor it.

1. Read the current file.
2. Insert the new entry at the requested position (default end).
3. Renumber if you like — purely cosmetic.
4. Commit on main:

   ```bash
   git add plans/MERGE_ORDER.md
   git commit -m "Queue: <branch> at position <N>"
   ```

### Remove (on merge or abandon)

1. Delete the entry.
2. Renumber.
3. Commit:

   ```bash
   git add plans/MERGE_ORDER.md
   git commit -m "Dequeue: <branch> (merged|abandoned)"
   ```

### Reorder (queue jump)

When the user yak-shaves or decides priority shifted:

1. Move the entry to the new position.
2. Commit:

   ```bash
   git add plans/MERGE_ORDER.md
   git commit -m "Reorder: <branch> -> position <N>"
   ```

Reordering does **not** trigger any rebases. Branches still live off `main`. The order only governs the merge sequence.

## Validation

Before any edit, sanity-check:

- Branch named in an entry actually exists (`git rev-parse --verify <branch>`). If not, flag to the user — the entry may be stale.
- No duplicate entries for the same branch.

Don't auto-fix; surface the issue.

## What this skill does NOT do

- Compute order from per-plan dependencies. The file is *agreed* order, not *derived* order.
- Decide when to merge. It just records intent.
- Touch any branch other than main.
- Rebase anything.
