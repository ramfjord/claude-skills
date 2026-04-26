#!/usr/bin/env bash
# test-isolation.sh — assert per-directory swank images are isolated.
#
# Bootstraps four images:
#   1. fixtures/elp                     (the main fixture)
#   2. fixtures/elp/worktrees/wt1       (git worktree of #1)
#   3. fixtures/elp/worktrees/wt2       (git worktree of #1)
#   4. /tmp/elp-isolation-$$/elp        (cp -r of #1; basename literally
#                                        'elp', same as #1 — the case
#                                        the realpath hash exists to fix)
#
# Asserts:
#   - 4 distinct .swank-session names (no two directories collide)
#   - 4 distinct .swank-port values
#   - 4 distinct SBCL PIDs owning those ports (proxy for state isolation:
#     different processes can't share Lisp state)
#
# The 4th case is the cross-project basename collision — same basename
# `elp` as #1, different realpath, must not collide.
#
# Cleanup tears down all four images via cleanup-swank.sh, removes the
# two git worktrees, and rms the temp clone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE="$REPO_ROOT/fixtures/elp"

if [[ ! -d "$FIXTURE" ]]; then
  echo "fixture missing: $FIXTURE" >&2
  echo "(per CLAUDE.md, clone https://github.com/ramfjord/elp there)" >&2
  exit 1
fi

WT1="$FIXTURE/worktrees/wt1"
WT2="$FIXTURE/worktrees/wt2"
COLLISION_PARENT="/tmp/elp-isolation-$$"
COLLISION="$COLLISION_PARENT/elp"   # basename literally 'elp', same as $FIXTURE
BRANCH1="iso-test-wt1-$$"
BRANCH2="iso-test-wt2-$$"

DIRS=("$FIXTURE" "$WT1" "$WT2" "$COLLISION")

cleanup() {
  for d in "${DIRS[@]}"; do
    [[ -d "$d" ]] && "$SCRIPT_DIR/cleanup-swank.sh" "$d" >/dev/null 2>&1 || true
  done
  git -C "$FIXTURE" worktree remove --force "$WT1" 2>/dev/null || true
  git -C "$FIXTURE" worktree remove --force "$WT2" 2>/dev/null || true
  git -C "$FIXTURE" branch -D "$BRANCH1" 2>/dev/null || true
  git -C "$FIXTURE" branch -D "$BRANCH2" 2>/dev/null || true
  rm -rf "$COLLISION_PARENT"
}
trap cleanup EXIT
cleanup  # drop any leftover state from a prior run

fail() { echo "FAIL: $*" >&2; exit 1; }

# Build the 3 ephemeral dirs.
git -C "$FIXTURE" worktree add -b "$BRANCH1" "$WT1" >/dev/null
git -C "$FIXTURE" worktree add -b "$BRANCH2" "$WT2" >/dev/null
mkdir -p "$COLLISION_PARENT"
cp -r "$FIXTURE" "$COLLISION"
# Strip the copied .git so the collision dir isn't tangled with the fixture's git state.
rm -rf "$COLLISION/.git"

# Bootstrap each and assert per-dir health.
for d in "${DIRS[@]}"; do
  "$SCRIPT_DIR/assert-swank-healthy.sh" "$d"
done

# Collect session names, ports, owning PIDs.
sessions=()
ports=()
pids=()
for d in "${DIRS[@]}"; do
  s="$(cat "$d/.swank-session")"
  p="$(cat "$d/.swank-port")"
  # ss -tlnp output: ... users:(("sbcl",pid=12345,fd=N)) ...
  # Pull the first pid= for the line matching :PORT$.
  pid="$(ss -tlnp 2>/dev/null | awk -v port=":$p" '$4 ~ port { print }' \
         | grep -oP 'pid=\K[0-9]+' | head -n1)"
  [[ -n "$pid" ]] || fail "no PID owning port $p (dir $d)"
  sessions+=("$s")
  ports+=("$p")
  pids+=("$pid")
done

# Distinctness: each sorted-uniq must equal the original count.
distinct() {
  local n="$1"; shift
  local got
  got="$(printf '%s\n' "$@" | sort -u | wc -l)"
  [[ "$got" -eq "$n" ]] || return 1
}

distinct 4 "${sessions[@]}" || fail "session names not all distinct: ${sessions[*]}"
distinct 4 "${ports[@]}"    || fail "ports not all distinct: ${ports[*]}"
distinct 4 "${pids[@]}"     || fail "SBCL PIDs not all distinct: ${pids[*]}"

# Cross-project collision check: dirs 1 and 4 share basename 'elp', so
# their session names must still differ (the hash suffix is what makes
# this work).
[[ "${sessions[0]}" == "elp-"* ]] || fail "fixture session name '${sessions[0]}' missing 'elp-' prefix"
[[ "${sessions[3]}" == "elp-"* ]] || fail "collision session name '${sessions[3]}' missing 'elp-' prefix"
[[ "${sessions[0]}" != "${sessions[3]}" ]] \
  || fail "cross-project basename collision: both 'elp' dirs got the same session name"

echo
echo "PASS: 4 isolated swank images"
for i in 0 1 2 3; do
  printf "  [%d] %s\n      session=%s port=%s pid=%s\n" \
    "$i" "${DIRS[$i]}" "${sessions[$i]}" "${ports[$i]}" "${pids[$i]}"
done

# --- merge-worktree teardown hand-off ---
# Exercise the mechanical sequence ramfjord:merge-worktree runs after
# a successful merge (the Claude-driven skill itself is not testable
# here, but the scripted bits are): cleanup-swank → worktree remove →
# branch delete. WT1 is the victim; WT2 stays around so the cleanup
# trap still has work to do.
echo
echo "Exercising merge-worktree teardown on $WT1 ..."

WT1_SESSION="${sessions[1]}"
"$SCRIPT_DIR/cleanup-swank.sh" "$WT1" >/dev/null
git -C "$FIXTURE" worktree remove "$WT1"
git -C "$FIXTURE" branch -d "$BRANCH1" 2>/dev/null \
  || git -C "$FIXTURE" branch -D "$BRANCH1"   # -d may refuse on unmerged test branch

tmux has-session -t "$WT1_SESSION" 2>/dev/null \
  && fail "tmux session $WT1_SESSION survived teardown"
[[ ! -d "$WT1" ]] || fail "worktree dir $WT1 survived teardown"
git -C "$FIXTURE" branch --list "$BRANCH1" | grep -q . \
  && fail "branch $BRANCH1 survived teardown"

echo "PASS: merge-worktree teardown removed session, worktree, branch"
