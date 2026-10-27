#!/bin/bash
# This user's own temp folders — USER_FOLDER, the @cache/ @temp/ @boot-temp/ rule
# tokens, and is_safe_target's second branch, in_user_folder. Off $HOME a target
# must sit strictly inside the folder's C, T or X, lexically and once its parent is
# resolved. See docs/DESIGN.md#user-folder.
#
# What the assertions below are shaped around:
#
#   * user_folder_ok is checked against real folders — this user's own, a folder
#     below it, and root's — since its whole job is telling those apart.
#   * everything else runs in a sandbox: $HOME moves to $TEST_HOME/home and the
#     folder is $TEST_HOME/uf/ab/cdef, outside it, so an acceptance can only come
#     from the new branch. As in test_safe_target.sh, every "must refuse" fixture
#     exists first, so the refusal comes from the rule under test.
#   * with no USER_FOLDER a token stays relative: it matches nothing, and no gate
#     accepts it. That is also all a cdm too old to know the tokens can do.

. "$(dirname "$0")/lib.sh"

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0; PARSED_OK=0; }
put() { mkdir -p "$(dirname "$1")"; echo x > "$1"; }

# ---- user_folder_ok, against the real folders --------------------------------------

REAL=$(user_folder)
assert_ok   "this user's folder is found"                 test -n "$REAL"
assert_ok   "...and has the shape and owner it must"      user_folder_ok "$REAL"
assert_fail "a folder below it is not the folder"         user_folder_ok "$REAL/C"
assert_fail "its parent is not the folder"                user_folder_ok "${REAL%/*}"
assert_fail "the unresolved /var spelling is refused"     user_folder_ok "/var/folders/${REAL#/private/var/folders/}"
assert_fail "\$HOME is not a per-user folder"             user_folder_ok "$HOME"
ROOTF=""
for d in /private/var/folders/zz/*; do
    [ -d "$d" ] && [ "$(stat -f %u "$d")" = 0 ] && { ROOTF="$d"; break; }
done
assert_ok   "premise: root's own folder exists"           test -n "$ROOTF"
assert_fail "a folder that is not this user's is refused" user_folder_ok "$ROOTF"

# ---- the sandbox ------------------------------------------------------------------

HOME="$TEST_HOME/home"; mkdir -p "$HOME"; HOME_P=$(cd -P "$HOME" && pwd -P)
mkdir -p "$TEST_HOME/uf/ab/cdef"
USER_FOLDER=$(cd -P "$TEST_HOME/uf/ab/cdef" && pwd -P)
UF="$USER_FOLDER"

# ---- expand_tilde -------------------------------------------------------------------

assert_eq "$UF/C/clang/ModuleCache"  "$(expand_tilde "@cache/clang/ModuleCache")"  "@cache/ is the folder's C"
assert_eq "$UF/T/node-compile-cache" "$(expand_tilde "@temp/node-compile-cache")"  "@temp/ is its T"
assert_eq "$UF/X/a.code_sign_clone/b" "$(expand_tilde "@boot-temp/a.code_sign_clone/b")" "@boot-temp/ is its X"
assert_eq "$HOME/.npm"               "$(expand_tilde "~/.npm")"                    "~ is still \$HOME"
assert_eq "@cachex/y"                "$(expand_tilde "@cachex/y")"                 "a near-miss is no token"
assert_eq "@cache/clang"             "$( USER_FOLDER=""; expand_tilde "@cache/clang" )" \
    "no folder: the token stays as written, a relative path"

# ---- in_user_folder, through is_safe_target -------------------------------------------

put "$UF/C/clang/ModuleCache/abc.pcm"
put "$UF/T/node-compile-cache/v26/x"
put "$UF/X/org.x.App.code_sign_clone/code_sign_clone.AbCdEf/App.app.bundle/f"
put "$UF/0/com.apple.x/state"
put "$UF/Z/other/x"
put "$TEST_HOME/outside/precious"
ln -s "$TEST_HOME/outside" "$UF/T/link"
ln -s "$UF/C" "$TEST_HOME/into-c"

assert_ok "a cache folder in C is reachable"   is_safe_target "$UF/C/clang/ModuleCache"
assert_ok "a file in C is reachable"           is_safe_target "$UF/C/clang/ModuleCache/abc.pcm"
assert_ok "a folder in T is reachable"         is_safe_target "$UF/T/node-compile-cache"
assert_ok "a clone in X is reachable"          is_safe_target "$UF/X/org.x.App.code_sign_clone/code_sign_clone.AbCdEf"
assert_ok "a symlink in T is itself reachable" is_safe_target "$UF/T/link"

assert_fail "the folder itself"           is_safe_target "$UF"
assert_fail "C itself"                    is_safe_target "$UF/C"
assert_fail "C/ with a slash"             is_safe_target "$UF/C/"
assert_fail "C/. — C again"               is_safe_target "$UF/C/."
assert_fail "a ./ segment"                is_safe_target "$UF/C/./clang"
assert_fail "0 — not a temp folder"       is_safe_target "$UF/0/com.apple.x"
assert_fail "any other folder in it"      is_safe_target "$UF/Z/other"
assert_fail "a .. segment"                is_safe_target "$UF/C/clang/../clang"
assert_fail "a path that does not exist"  is_safe_target "$UF/C/nope"
# Written with the resolved folder, so the lexical check passes and only
# resolving the parent can refuse it.
assert_fail "a symlinked component escapes T" is_safe_target "$UF/T/link/precious"
# The mirror image: lexically outside, physically inside C. Only the lexical
# check refuses it.
assert_fail "a path outside that resolves into C" is_safe_target "$TEST_HOME/into-c/clang"
# In a subshell, so the empty USER_FOLDER does not outlive the assertion.
gate_without_folder() { ( USER_FOLDER=""; is_safe_target "$1" ); }
assert_fail "no folder: nothing in it is reachable" gate_without_folder "$UF/C/clang/ModuleCache"

# And the receipt: a delete goes through the gate.
t_out=$(delete_path rm "$UF/0/com.apple.x" 2>&1)
assert_ok "outside C, T and X a delete is skipped" test -e "$UF/0/com.apple.x/state"
assert_ok "...and the receipt says so" grep -q "skip (unsafe)" <<EOF
$t_out
EOF

# ---- the shipped rows -----------------------------------------------------------------

reset_cats
parse_pattern_stream "$CDM_ROOT/rules/dev-caches.json"
row() {
    local i
    for i in $(cat_indices); do
        [ "${CAT_NAME[$i]}" = "$1" ] && { printf '%s|%s' "${CAT_DEFAULT[$i]}" "${CAT_PATHS[$i]}"; return; }
    done
}
assert_eq "1|$UF/C/clang/ModuleCache" "$(row "Clang module cache")" "clang's module cache, pre-selected"
assert_eq "1|$UF/T/node-compile-cache" "$(row "Node / npm cache")" "Node's compile cache joins the npm row"

delete_path rm "$UF/C/clang/ModuleCache" >/dev/null 2>&1
assert_ok "a shipped row's folder is deleted" test ! -e "$UF/C/clang/ModuleCache"

reset_cats
USER_FOLDER=""
parse_pattern_stream "$CDM_ROOT/rules/dev-caches.json"
assert_eq "" "$(row "Node / npm cache")" "no folder: a token path matches nothing"

test_summary
