#!/usr/bin/env bash
# Assert every commit on main..<branch> touches the plan file.
#
# Usage: check-plan-coverage.sh <branch> <plan-path>
#
# Exits 0 if every commit's diff includes <plan-path>.
# Exits 1 (and lists offending commits) otherwise.
#
# Used by ramfjord-merge-worktree's preflight to detect commits that
# bypassed do-plan's contract of staging plan + code together.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <branch> <plan-path>" >&2
  exit 2
fi

branch="$1"
plan="$2"
base="main"

if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
  echo "branch not found: $branch" >&2
  exit 2
fi

if ! git rev-parse --verify "$base" >/dev/null 2>&1; then
  echo "base branch not found: $base" >&2
  exit 2
fi

# List commits on branch that aren't on main.
commits=$(git rev-list "$base..$branch")

if [[ -z "$commits" ]]; then
  echo "no commits between $base and $branch — nothing to check"
  exit 0
fi

offenders=()
while IFS= read -r sha; do
  if ! git show --name-only --format= "$sha" | grep -qxF "$plan"; then
    offenders+=("$sha")
  fi
done <<< "$commits"

if [[ ${#offenders[@]} -eq 0 ]]; then
  echo "all commits on $base..$branch touch $plan"
  exit 0
fi

echo "commits on $base..$branch that do not touch $plan:" >&2
for sha in "${offenders[@]}"; do
  subj=$(git log -1 --format='%h %s' "$sha")
  echo "  $subj" >&2
done
exit 1
