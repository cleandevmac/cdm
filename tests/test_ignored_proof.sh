#!/bin/bash
# A name-matched dir is junk only when git says the project ignores it.
#
# The find pass knows nothing but basenames, and "dist", "build", "out", "Pods",
# "target", "venv" and friends are all names a project may legitimately TRACK:
# build/ holding release scripts, out/ holding generated-but-committed assets,
# Pods/ vendored on purpose, a dist/ committed for consumers. Matching the name
# alone offered every one of those for permanent `rm`. So scan_projects now
# proves each candidate is git-ignored — via the same per-repo
# `git ls-files --others --ignored --directory` the git-ignored category uses —
# and drops whatever it cannot prove. see docs/DESIGN.md#ignored-proof
#
# This drives scan_projects end-to-end against real repos so it exercises the
# actual git output, not a reimplementation of it. GI_ON=0 throughout: with the
# git-ignored category off, EVERY offered path had to come through the
# name-matched branch, which is the branch under test.
#
# The negatives alone ("build absent") would pass a scan that found NOTHING —
# the exact way this could rot into false coverage — so every case is paired
# with a positive that must still be offered.

. "$(dirname "$0")/lib.sh"

if ! command -v git >/dev/null 2>&1; then
    printf '%-28s  skipped (no git)\n' "$T_FILE"
    exit 0
fi

git_init() {
    ( cd "$1" && git init -q ) || { printf '%s: git init failed\n' "$T_FILE" >&2; exit 1; }
}
commit_all() {
    ( cd "$1" && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) \
        || { printf '%s: git commit failed\n' "$T_FILE" >&2; exit 1; }
}

# --- repo A: the three states a candidate dir can be in ---------------------
#   dist   ignored, untracked      -> junk
#   build  TRACKED (build scripts) -> not junk, must survive
#   out    untracked, NOT ignored  -> unproven, must survive
a="$HOME/code/repoA"
mkdir -p "$a/dist" "$a/build" "$a/out"
git_init "$a"
printf '%s\n' dist > "$a/.gitignore"
: > "$a/dist/bundle.js"
: > "$a/build/release.sh"
: > "$a/out/generated.txt"
commit_all "$a"

# --- repo B: ignore-listed, but the directory holds a TRACKED file ----------
# `git add -f` after listing it is a real pattern (a library shipping its built
# dist/). check-ignore alone would call this ignored; ls-files --directory does
# not collapse a directory containing tracked content, so it stays.
b="$HOME/code/repoB"
mkdir -p "$b/dist" "$b/node_modules"
git_init "$b"
printf '%s\n' dist node_modules > "$b/.gitignore"
: > "$b/dist/committed.js"
: > "$b/node_modules/pkg.js"
( cd "$b" && git add -A && git add -f dist/committed.js ) >/dev/null 2>&1
commit_all "$b"

# --- repo C: candidate under an ancestor that --directory collapsed ---------
# .gitignore hides all of tmpstuff/, so git reports "tmpstuff/" and never
# "tmpstuff/dist". The proof must accept an ancestor, not just an exact hit.
c="$HOME/code/repoC"
mkdir -p "$c/tmpstuff/dist"
git_init "$c"
printf '%s\n' tmpstuff > "$c/.gitignore"
: > "$c/tmpstuff/dist/x.js"
commit_all "$c"

# --- repo D: no git repo at all ---------------------------------------------
# Not a repo, so there is nothing to prove anything with. Already skipped by
# project_key; pinned here so the two reasons stay independent.
mkdir -p "$HOME/notarepo/node_modules"

# --- repos E/E-inner: an outer repo that ignores a nested checkout -----------
# outer/.gitignore hides inner/, so the OUTER listing reports "inner/" — but
# inner is its own repo and TRACKS inner/build. The proof must be read in the
# candidate's own repo: the outer repo's opinion of inner/ says nothing about
# what inner tracks. The outer repo also carries its own ignored node_modules,
# which is what puts it in the scan's git pass at all.
e="$HOME/code/repoE"
mkdir -p "$e/node_modules" "$e/inner/build"
git_init "$e"
printf '%s\n' node_modules inner > "$e/.gitignore"
: > "$e/node_modules/pkg.js"
: > "$e/inner/build/release.sh"
git_init "$e/inner"
commit_all "$e/inner"
commit_all "$e"

# scan_projects reads its config from these (normally filled by load_patterns).
# GI_ON=0 isolates the name-matched branch: nothing may arrive via git ls-files
# as a git-ignored OFFER, only as the proof this branch consults.
PROJECTS_ENABLED=1
GI_ON=0
GI_METHOD="trash"
PROJ_N=1
PROJ_DIRS=("node_modules
dist
build
out")
PROJ_METHOD=("rm")
SCAN_ROOTS=("$HOME")
SCAN_DEPTH=6
SCAN_MAXREPOS=400
SCAN_PRUNE=()
SCAN_GROUPS=()

CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=(); CAT_PROCS=()
N=0
scan_projects

paths=$(printf '%s\n' "${CAT_PATHS[@]+"${CAT_PATHS[@]}"}" | grep -v '^$')
offered() { printf '%s\n' "$paths" | grep -qxF "$1"; }

# --- the positives: proof exists, so the junk IS offered --------------------
# Without these every assertion below would pass on an empty scan.
assert_ok 'an ignored dist/ IS offered — proves the scan ran' \
    offered "$a/dist"
assert_ok 'an ignored node_modules/ IS offered' \
    offered "$b/node_modules"
assert_ok 'a candidate under a collapsed ignored ancestor IS offered' \
    offered "$c/tmpstuff/dist"
assert_ok 'the outer repo of a nested pair still offers its own ignored junk' \
    offered "$e/node_modules"

# --- the guarantee: no proof, no offer --------------------------------------
assert_fail 'a TRACKED build/ is never offered' \
    offered "$a/build"
assert_fail 'an untracked but un-ignored out/ is never offered' \
    offered "$a/out"
assert_fail 'an ignore-listed dist/ holding a tracked file is never offered' \
    offered "$b/dist"
assert_fail 'a node_modules/ outside any repo is never offered' \
    offered "$HOME/notarepo/node_modules"
assert_fail "an outer repo ignoring a nested checkout cannot condemn what that checkout tracks" \
    offered "$e/inner/build"

# Nothing tracked leaks in by another route: the five paths above are every
# non-ignored candidate in the sandbox, so the offer set must be exactly the
# four proven ones.
assert_eq 4 "$(printf '%s\n' "$paths" | grep -c .)" \
    'exactly the four proven items are offered, nothing else'

test_summary
