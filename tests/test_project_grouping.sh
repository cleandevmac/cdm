#!/bin/bash
# Sibling repos under a shared parent collapse into ONE aggregate row.
#
# cdm's project scan emits one category per git repo. A directory full of
# machine-generated repos (each its own .git — e.g. an AI agent's per-session
# "brain" store) then floods the menu with dozens of near-identical rows. So any
# parent dir holding >=2 repo roots is grouped: its repos become a single row
# keyed by the parent, with the item paths and per-path methods preserved intact
# (grouping is a display/bucketing decision — is_safe_target still gates every
# path). see docs/DESIGN.md#sibling-grouping
#
# This drives scan_projects end-to-end against a sandbox tree so it exercises the
# real find pass, the key remap folded into the dedup awk, and the repo-count
# prefix in flush_project_category — not a reimplementation of any of them.

. "$(dirname "$0")/lib.sh"

# --- a sandbox of git repos -------------------------------------------------
# Two siblings under ~/brain (must group) and one lone repo under ~/solo (must
# not). Name-matched junk (node_modules) rather than git-ignored files, so the
# scan needs only `find` + a real .git DIRECTORY, not a working `git` binary.
mkrepo() { mkdir -p "$1/.git" "$1/node_modules"; }
mkrepo "$HOME/brain/aaaaaaaa-1111"
mkrepo "$HOME/brain/bbbbbbbb-2222"
mkrepo "$HOME/solo"

# scan_projects reads its config from these (normally filled by load_patterns).
PROJECTS_ENABLED=1
GI_ON=0
PROJ_N=1
PROJ_DIRS=("node_modules")
PROJ_METHOD=("rm")
SCAN_ROOTS=("$HOME")
SCAN_DEPTH=6
SCAN_MAXREPOS=400
SCAN_PRUNE=()

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

assert_eq 2 "$N" 'two rows: one grouped (brain), one lone (solo)'

# --- the group row ----------------------------------------------------------
gi=$(cat_index "brain")
assert_ok 'a category is named for the shared parent ~/brain' test -n "$gi"
if [ -n "$gi" ]; then
    assert_eq "~/brain" "${CAT_NAME[$gi]}" 'grouped row is keyed by the parent, not a repo'
    # The two siblings' node_modules both land under the one grouped category.
    assert_eq 2 "$(printf '%s\n' "${CAT_PATHS[$gi]}" | grep -c 'node_modules')" \
        'both siblings'"'"' junk is bucketed into the grouped row'
    # Summary leads with the repo count.
    case "${CAT_SUMMARY[$gi]}" in
        "2 repos · "*) assert_ok 'summary leads with the repo count' true ;;
        *) assert_ok "summary leads with '2 repos · ' (got [${CAT_SUMMARY[$gi]}])" false ;;
    esac
fi

# --- the lone row -----------------------------------------------------------
si=$(cat_index "solo")
assert_ok 'the lone repo keeps its own row' test -n "$si"
if [ -n "$si" ]; then
    # A single repo is NOT a group: no count prefix.
    case "${CAT_SUMMARY[$si]}" in
        *"repos · "*) assert_ok "lone repo must not get a 'repos ·' prefix (got [${CAT_SUMMARY[$si]}])" false ;;
        *) assert_ok 'lone repo has no repo-count prefix' true ;;
    esac
fi

test_summary
