#!/usr/bin/env bash
# test.sh — exercise check-plan-coverage.sh against a temp git repo.
#
# Cases covered:
#   1. All commits touch the plan         → pass
#   2. One commit doesn't touch the plan  → fail, lists that commit
#   3. Multiple offending commits         → fail, lists all of them
#   4. Empty range (branch == main)       → pass ("nothing to check")
#   5. Nonexistent branch                 → exit 2 (usage / setup error)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-plan-coverage.sh"
WORK="/tmp/check-plan-coverage-test-$$"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- fixture setup ---
mkdir -p "$WORK"
cd "$WORK"

git init -q -b main
git config user.email t@example.com
git config user.name test

mkdir plans
echo "# initial plan" > plans/x.md
echo "code" > code.txt
git add . && git commit -q -m "initial"

git checkout -q -b feature

# Commit A: touches plan + code (good)
echo "edit 1" >> code.txt
echo "## Commits" >> plans/x.md
git add . && git commit -q -m "A: plan + code"

# Commit B: touches only code (offender)
echo "edit 2" >> code.txt
git add . && git commit -q -m "B: code only"

# Commit C: touches plan + code (good)
echo "edit 3" >> code.txt
echo "more plan" >> plans/x.md
git add . && git commit -q -m "C: plan + code"

# Commit D: touches only code (second offender)
echo "edit 4" >> code.txt
git add . && git commit -q -m "D: code only"

# --- case 1: all-good branch (subset feature^^^^..feature^^^ doesn't help; use a fresh branch) ---
git checkout -q -b clean main
echo "edit 1" >> code.txt
echo "addition" >> plans/x.md
git add . && git commit -q -m "clean: plan + code"

# --- run cases ---

# Case 1: all commits on `clean` touch plans/x.md → pass
out=$("$SCRIPT" clean plans/x.md) \
  || fail "case 1: expected pass, script exited non-zero. output: $out"
echo "$out" | grep -q "all commits" \
  || fail "case 1: expected 'all commits' message, got: $out"

# Case 2 + 3: feature has two offenders (B and D)
if out=$("$SCRIPT" feature plans/x.md 2>&1); then
  fail "case 2/3: expected fail, script exited 0. output: $out"
fi
echo "$out" | grep -q "B: code only" \
  || fail "case 2: expected B to be flagged, got: $out"
echo "$out" | grep -q "D: code only" \
  || fail "case 3: expected D to be flagged, got: $out"
# Good commits (A, C) must NOT be in the offender list
echo "$out" | grep -q "A: plan + code" \
  && fail "case 2: A wrongly flagged as offender"
echo "$out" | grep -q "C: plan + code" \
  && fail "case 2: C wrongly flagged as offender"

# Case 4: empty range (main..main) → pass with "nothing to check"
out=$("$SCRIPT" main plans/x.md) \
  || fail "case 4: expected pass on empty range, got non-zero. output: $out"
echo "$out" | grep -q "nothing to check" \
  || fail "case 4: expected 'nothing to check', got: $out"

# Case 5: nonexistent branch → exit 2
set +e
"$SCRIPT" no-such-branch plans/x.md >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "case 5: expected exit 2 on missing branch, got $rc"

echo "PASS: check-plan-coverage.sh handles all 5 cases"
