#!/bin/bash
# The "code-sign-clones" rule kind (register_clones and its helpers) — the copy of
# its app bundle a Chromium browser clones at every launch and deletes only on a
# clean exit. One row for the copies left behind, sized by what they alone hold,
# deleted with one receipt line. See docs/DESIGN.md#code-sign-clones.
#
# What the assertions below are shaped around:
#
#   * what is KEPT: a copy a running browser may use (born within five minutes
#     after it started), one younger than five minutes (a launch in progress), and
#     every copy when there is no process list. ps is a shell function here, and
#     birth times are set with touch -t, which on APFS moves the birth time back.
#   * the size is not du's: a copy of a version still installed holds only its
#     metadata (entries / CLONE_ENTRIES_PER_KB); a copy of a version no longer
#     installed holds that version's blocks too — counted once per version.
#   * the clean deletes through is_safe_target, with one line for the lot.

. "$(dirname "$0")/lib.sh"

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0; PARSED_OK=0; }

# A sandboxed per-user folder outside $HOME, as in test_user_folder.sh.
HOME="$TEST_HOME/home"; mkdir -p "$HOME"; HOME_P=$(cd -P "$HOME" && pwd -P)
mkdir -p "$TEST_HOME/uf/ab/cdef/X"
USER_FOLDER=$(cd -P "$TEST_HOME/uf/ab/cdef" && pwd -P)
CL="$USER_FOLDER/X/org.fakium.Fakium.code_sign_clone"

NOW=$(date +%s)
# mkclone <suffix> <version> <age in seconds> — a clone of Fakium <version>.
mkclone() {
    local c="$CL/code_sign_clone.$1"
    local v="$c/Fakium.app.bundle/Contents/Frameworks/Fakium Framework.framework/Versions/$2"
    mkdir -p "$v/Resources" "$c/Fakium.app.bundle/Contents/MacOS"
    # Big enough that the blocks a removed version holds never round to nothing.
    dd if=/dev/zero of="$v/Resources/resources.pak" bs=1024 count=64 2>/dev/null
    echo x > "$c/Fakium.app.bundle/Contents/MacOS/Fakium"
    touch -t "$(date -r $((NOW - $3)) +%Y%m%d%H%M.%S)" "$c"
}
# Fakium 2.0 is installed; 1.0 is gone. The running Fakium started 6000 s ago.
mkdir -p "$HOME/Applications/Fakium.app/Contents/Frameworks/Fakium Framework.framework/Versions/2.0"
mkclone aaaaaa 2.0 5998     # born 2 s after the running Fakium started: its copy
mkclone bbbbbb 2.0 7200     # from an earlier launch
mkclone cccccc 2.0 172800   # two days old
mkclone dddddd 1.0 90000    # a version no longer installed
mkclone eeeeee 1.0 95000
mkclone ffffff 2.0 60       # a launch still in progress
mkdir -p "$CL/code_sign_clone.hhhhhh"; echo x > "$CL/code_sign_clone.hhhhhh/stray"
touch -t "$(date -r $((NOW - 7200)) +%Y%m%d%H%M.%S)" "$CL/code_sign_clone.hhhhhh"

T_PS="  01:40:00 /Applications/Fakium.app/Contents/MacOS/Fakium --type=browser
     00:03 /bin/bash ./cdm
  1-02:00:00 /Applications/Other.app/Contents/MacOS/Other"
ps() { printf '%s\n' "$T_PS"; }

# ---- app_starts -----------------------------------------------------------------------

t_starts=$(printf '%s\n' "  1-02:03:04 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --x" \
    "     12:34 /Applications/Fakium.app/Contents/MacOS/Fakium" \
    "  00:05 /usr/bin/ssh host" \
    "  01:00 /A/B b.app/Contents/Frameworks/F.framework/Helpers/B b Helper.app/Contents/MacOS/B b Helper" |
    app_starts "$NOW" | tr '\037' '|')
assert_eq "Google Chrome|$((NOW - 93784))
Fakium|$((NOW - 754))
B b Helper|$((NOW - 60))" "$t_starts" "start times from ps's elapsed time, days included; a helper is its own app"

# ---- clone_version_shared ----------------------------------------------------------

assert_ok   "an installed version is shared"   clone_version_shared Fakium 2.0
assert_fail "a removed version is not"         clone_version_shared Fakium 1.0
assert_fail "an app nobody installed is not"   clone_version_shared Nopium 2.0

# ---- register_clones ----------------------------------------------------------------

reset_cats
register_clones "👥" "Leftover copies" 1 "D." "@boot-temp/*.code_sign_clone/code_sign_clone.*"
assert_eq "1" "$N" "one row"
assert_eq "$CL/code_sign_clone.bbbbbb
$CL/code_sign_clone.cccccc
$CL/code_sign_clone.dddddd
$CL/code_sign_clone.eeeeee
$CL/code_sign_clone.hhhhhh" "${CAT_PATHS[0]:-}" \
    "offered: every leftover copy; kept: the running browser's and a launch in progress"
assert_eq "clones|1|5 copies" "${CAT_METHOD[0]:-}|${CAT_DEFAULT[0]:-}|${CAT_SUMMARY[0]:-}" \
    "method clones, the rule's default, and a count"
# Each Fakium copy has 11 entries: two 2.0 copies and two 1.0 copies hold 22/3 KiB
# of metadata apiece; only 1.0's blocks, once, are held by its copies alone. The
# stray copy's 2 entries round to nothing.
t_want=$(( 2 * 11 / 3 + 2 * 11 / 3 + $(du_kb "$CL/code_sign_clone.dddddd") ))
assert_eq "$t_want" "${CAT_KB[0]:-}" "sized by what the copies alone hold, not by du"
compute_sizes_write; compute_sizes_read
assert_eq "$t_want" "${CAT_KB[0]:-}" "...and the sizing pass keeps that figure"

CURSOR=0
assert_ok "details list the copies without a du each" grep -q "Copies (5 copies" <<EOF
$(show_details 2>&1)
EOF

# No process list: no copy can be told from the one a browser runs on.
reset_cats
T_PS=""
register_clones "👥" "Leftover copies" 1 "D." "@boot-temp/*.code_sign_clone/code_sign_clone.*"
assert_eq "0" "$N" "no process list: nothing offered"
T_PS="  01:40:00 /Applications/Fakium.app/Contents/MacOS/Fakium --type=browser"

# ---- the clean -------------------------------------------------------------------------

reset_cats
register_clones "👥" "Leftover copies" 1 "D." "@boot-temp/*.code_sign_clone/code_sign_clone.*"
CAT_SEL[0]=1; NON_INTERACTIVE=1; DRY_RUN=0
t_out=$(run_cleanup 2>&1)
assert_ok "the plan marks the row DELETE" grep -q 'DELETE.*Leftover copies' <<EOF
$t_out
EOF
assert_ok "one receipt line for the lot" grep -q 'deleted:.* 5 copies' <<EOF
$t_out
EOF
t_left=""; for c in "$CL"/code_sign_clone.*; do t_left="$t_left ${c##*.}"; done
assert_eq " aaaaaa ffffff" "$t_left" "the leftovers are gone; the running browser's copy and the new one stay"
NON_INTERACTIVE=0

mkdir -p "$TEST_HOME/outside/code_sign_clone.zzzzzz"; echo x > "$TEST_HOME/outside/code_sign_clone.zzzzzz/f"
t_out=$(run_clone_delete "$TEST_HOME/outside/code_sign_clone.zzzzzz" 2>&1)
assert_ok "a path the gate refuses is not deleted" test -e "$TEST_HOME/outside/code_sign_clone.zzzzzz/f"
assert_ok "...and the receipt says so" grep -q "skip (unsafe)" <<EOF
$t_out
EOF

# ---- the shipped rule ----------------------------------------------------------------

mkclone gggggg 2.0 7200
reset_cats
parse_pattern_stream "$CDM_ROOT/rules/app-caches.json"
t_row=""
for i in $(cat_indices); do
    [ "${CAT_METHOD[$i]}" = "clones" ] && t_row="${CAT_NAME[$i]}|${CAT_DEFAULT[$i]}|${CAT_PATHS[$i]}"
done
assert_eq "Leftover Chrome app copies|1|$CL/code_sign_clone.gggggg" "$t_row" \
    "shipped app-caches.json: Chromium's leftover copies in X, pre-selected"

test_summary
