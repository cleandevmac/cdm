#!/bin/bash
# Nothing that holds another git checkout, or sits inside one, is ever offered.
#
# A repo may git-ignore a folder that holds a whole other checkout: Claude Code
# keeps its git worktrees in a git-ignored .claude/worktrees, people vendor a
# clone into an ignored vendor/, and a parent repo may ignore a child repo
# outright. `git ls-files --others --ignored --directory` reports such a folder
# as one ignored entry, so the git-ignored pass offered it for the Trash —
# worktrees, their uncommitted work and nested clones included. The find pass
# never saw those checkouts: it counts only a .git DIRECTORY as a repo (a
# worktree's or submodule's .git is a file) and it never enters pruned names
# such as .claude or vendor. So scan_projects now probes every offered path.
# see docs/DESIGN.md#other-checkouts
#
# The negatives alone would pass a scan that found NOTHING, so the positives
# below must still be offered: the outer repo's own node_modules (with a .git
# folder in it that is no checkout), and the nested repo's own junk, which its
# own git vouches for.

. "$(dirname "$0")/lib.sh"

if ! command -v git >/dev/null 2>&1; then
    printf '%-28s  skipped (no git)\n' "$T_FILE"
    exit 0
fi

in_repo() {
    local dir="$1"; shift
    ( cd "$dir" && "$@" ) >/dev/null 2>&1 || { printf '%s: %s failed in %s\n' "$T_FILE" "$*" "$dir" >&2; exit 1; }
}

# --- the outer repo -----------------------------------------------------------
# It commits a build/ of release scripts, so a worktree of it checks that build/
# out as TRACKED content — which the outer repo's ignore of wt/ must not condemn.
f="$HOME/code/repoF"
mkdir -p "$f/build" "$f/node_modules/odd/.git" "$f/cache/locked"
printf '%s\n' node_modules wt vendor inner cache .claude/worktrees > "$f/.gitignore"
: > "$f/build/release.sh"
: > "$f/node_modules/pkg.js"
: > "$f/node_modules/odd/.git/config"     # a .git folder with no HEAD is no checkout
: > "$f/cache/locked/blob"
in_repo "$f" git init -q
in_repo "$f" git add -A
in_repo "$f" git -c user.email=t@t -c user.name=t commit -qm init

# A worktree in an ignored folder the find pass DOES enter: its .git is a file.
in_repo "$f" git worktree add -q wt/feature
: > "$f/wt/feature/uncommitted.txt"
mkdir -p "$f/wt/feature/node_modules"
: > "$f/wt/feature/node_modules/pkg.js"

# A Claude Code worktree, under a name the rules prune.
in_repo "$f" git worktree add -q .claude/worktrees/agent-1

# A clone vendored into an ignored, pruned folder, and a child repo the outer
# repo ignores whole. The child's own ignored junk is its own git's to vouch for.
mkdir -p "$f/vendor/lib" "$f/inner/node_modules"
in_repo "$f/vendor/lib" git init -q
printf '%s\n' node_modules > "$f/inner/.gitignore"
: > "$f/inner/node_modules/pkg.js"
in_repo "$f/inner" git init -q

# A folder find cannot read might hold anything, so it must not be offered.
chmod 000 "$f/cache/locked"

PROJECTS_ENABLED=1
GI_ON=1
GI_METHOD="trash"
PROJ_N=1
PROJ_DIRS=("node_modules
build")
PROJ_METHOD=("rm")
SCAN_ROOTS=("$HOME")
SCAN_DEPTH=6
SCAN_MAXREPOS=400
SCAN_PRUNE=(".claude" "vendor")
SCAN_GROUPS=()

CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=(); CAT_PROCS=()
N=0
scan_projects

# Restored before any assertion, so the sandbox can always be removed.
chmod 755 "$f/cache/locked"

paths=$(printf '%s\n' "${CAT_PATHS[@]+"${CAT_PATHS[@]}"}" | grep -v '^$')
offered() { printf '%s\n' "$paths" | grep -qxF "$1"; }
offered_under() { printf '%s\n' "$paths" | grep -qF "$1/"; }

# --- the positives: the scan ran, and ordinary junk is still offered ---------
assert_ok "the outer repo's own node_modules IS offered — proves the scan ran" \
    offered "$f/node_modules"
assert_ok "a nested repo's own junk IS still offered, on its own git's say-so" \
    offered "$f/inner/node_modules"

# --- the guarantee ------------------------------------------------------------
assert_fail 'a folder holding a git worktree is never offered' \
    offered "$f/wt"
assert_fail 'a folder holding a Claude Code worktree is never offered' \
    offered "$f/.claude"
assert_fail '...nor any path under it' \
    offered_under "$f/.claude"
assert_fail 'a folder holding a vendored clone is never offered' \
    offered "$f/vendor"
assert_fail 'a nested repo the outer repo ignores is never offered whole' \
    offered "$f/inner"
assert_fail "a worktree's TRACKED build/ is never offered on the outer repo's word" \
    offered "$f/wt/feature/build"
assert_fail "...nor a worktree's node_modules" \
    offered "$f/wt/feature/node_modules"
assert_fail 'a folder find cannot read is never offered' \
    offered "$f/cache"

assert_eq 2 "$(printf '%s\n' "$paths" | grep -c .)" \
    'exactly the two vouched-for items are offered, nothing else'
assert_ok "the worktree's uncommitted work is untouched" \
    test -e "$f/wt/feature/uncommitted.txt"

test_summary
