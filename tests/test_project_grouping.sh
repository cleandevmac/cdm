#!/bin/bash
# A configured group root collapses every repo beneath it into ONE aggregate row.
#
# cdm's project scan emits one category per git repo. A directory full of
# machine-generated repos (each its own .git — e.g. an AI agent that keeps each
# session as its own repo under ~/.gemini/antigravity/brain) then floods the menu
# with dozens of near-identical rows. So the rules name such directories in
# scan.groups; every repo at or under a group root becomes a single row keyed by
# the root, with the item paths and per-path methods preserved intact (grouping is
# a display/bucketing decision — is_safe_target still gates every path). Grouping
# is NAMED, not inferred: a directory that is not listed is never grouped, so real
# hand-managed sibling projects keep their own rows. see docs/DESIGN.md#group-roots
#
# This drives scan_projects end-to-end against a sandbox tree so it exercises the
# real find pass, the group-root remap folded into the dedup awk, and the
# repo-count prefix in flush_project_category — not a reimplementation of any.

. "$(dirname "$0")/lib.sh"

# --- a sandbox of git repos -------------------------------------------------
# Two repos under a configured group root (must collapse), and two UNCONFIGURED
# siblings elsewhere (must each keep their own row — grouping is named, not by
# count). Name-matched junk (node_modules/dist) rather than git-ignored files, so
# the scan needs only `find` + a real .git DIRECTORY, not a working `git` binary.
# The FIRST grouped repo holds TWO junk dirs: the group then spans 3 items but only
# 2 repos, so the row's "N repos" count must dedup by repo, not tally items.
mkrepo() { mkdir -p "$1/.git" "$1/node_modules"; }
mkrepo "$HOME/store/aaaaaaaa-1111"; mkdir -p "$HOME/store/aaaaaaaa-1111/dist"
mkrepo "$HOME/store/bbbbbbbb-2222"
mkrepo "$HOME/code/projA"
mkrepo "$HOME/code/projB"

# scan_projects reads its config from these (normally filled by load_patterns).
PROJECTS_ENABLED=1
GI_ON=0
PROJ_N=1
PROJ_DIRS=("node_modules
dist")
PROJ_METHOD=("rm")
SCAN_ROOTS=("$HOME")
SCAN_DEPTH=6
SCAN_MAXREPOS=400
SCAN_PRUNE=()
SCAN_GROUPS=("~/store")          # only ~/store is a group root; ~/code is not

# Fresh category arrays, then scan.
CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=(); CAT_PROCS=()
N=0
scan_projects

# --- helpers ----------------------------------------------------------------
# Index of the one category whose name ends in <suffix>, or empty.
cat_index() {
    local i=0
    while [ "$i" -lt "$N" ]; do
        case "${CAT_NAME[$i]}" in *"$1") printf '%s' "$i"; return ;; esac
        i=$((i + 1))
    done
}

# Three rows: one grouped (~/store) + two lone (~/code/projA, ~/code/projB).
assert_eq 3 "$N" 'group root yields one row; unconfigured siblings stay separate'

# --- the grouped row --------------------------------------------------------
gi=$(cat_index "store")
assert_ok 'a category is named for the group root ~/store' test -n "$gi"
if [ -n "$gi" ]; then
    assert_eq "~/store" "${CAT_NAME[$gi]}" 'grouped row is keyed by the group root, not a repo'
    # All three junk dirs beneath the root land under the one grouped category...
    assert_eq 3 "$(printf '%s\n' "${CAT_PATHS[$gi]}" | grep -cE '/node_modules$|/dist$')" \
        'all items under the root are bucketed into the grouped row'
    # ...but they come from only two repos, and the count must say so (not "3").
    case "${CAT_SUMMARY[$gi]}" in
        "2 repos · "*) assert_ok 'summary counts contributing repos, deduped (2, not 3 items)' true ;;
        *) assert_ok "summary leads with '2 repos · ' (got [${CAT_SUMMARY[$gi]}])" false ;;
    esac
fi

# --- the UNCONFIGURED siblings ----------------------------------------------
# ~/code is not a group root, so its two repos are NOT merged and get no prefix.
assert_ok 'unconfigured ~/code/projA keeps its own row' test -n "$(cat_index 'code/projA')"
assert_ok 'unconfigured ~/code/projB keeps its own row' test -n "$(cat_index 'code/projB')"
ci=$(cat_index "code/projA")
if [ -n "$ci" ]; then
    case "${CAT_SUMMARY[$ci]}" in
        *"repos · "*|*"repo · "*) assert_ok "ungrouped repo must not get a count prefix (got [${CAT_SUMMARY[$ci]}])" false ;;
        *) assert_ok 'ungrouped repo has no repo-count prefix' true ;;
    esac
fi

test_summary
