#!/bin/bash
# is_safe_target (cdm:278) — the gate every deletion passes through, and the one
# function here where a false positive means destroying a stranger's data.
#
# Ordering trap, and the reason so many fixtures below get mkdir'd first: the
# existence check (`[ -e "$p" ] || return 1`, cdm:287) runs BEFORE the
# protected-set case (cdm:289). Assert that ~/Documents is refused without
# creating it and the assertion passes for the wrong reason — the path was
# merely absent — and it would keep passing with the entire protected block
# deleted. Every "must refuse" fixture is therefore made to exist first, so the
# refusal can only come from the rule under test.

. "$(dirname "$0")/lib.sh"

# ---- fixtures --------------------------------------------------------------

# The protected set, per CLAUDE.md and cdm:289-295. These must exist for the
# refusals below to prove anything.
for d in Documents Desktop Downloads Pictures Movies Music .ssh .gnupg \
         "Library/Mobile Documents"; do
    mkdir -p "$HOME/$d" || exit 1
done

# A legitimate target: a regenerable cache under the home tree.
mkdir -p "$HOME/Library/Caches/com.example.app" || exit 1
: > "$HOME/Library/Caches/com.example.app/blob"

# A directory outside the home tree, plus a symlink pointing at it. This is the
# attack the physical-containment check exists to stop: the path is lexically
# under $HOME, so only resolving the parent catches that it isn't really.
OUTSIDE=$(mktemp -d "${TMPDIR:-/tmp}/cdm-test-outside.XXXXXX") || exit 1
: > "$OUTSIDE/precious"
ln -s "$OUTSIDE" "$HOME/escape-hatch"
# And the mirror image: a link OUTSIDE the home tree that points back INTO it.
ln -s "$HOME/Library/Caches" "$OUTSIDE/into-home"
trap 'rm -rf "$OUTSIDE"; _cdm_test_cleanup' EXIT

# ---- accepts ---------------------------------------------------------------

assert_ok "a cache dir under \$HOME is reachable" \
    is_safe_target "$HOME/Library/Caches/com.example.app"
assert_ok "a file under \$HOME is reachable" \
    is_safe_target "$HOME/Library/Caches/com.example.app/blob"

# ---- refuses: degenerate paths ---------------------------------------------

assert_fail "empty path"          is_safe_target ""
assert_fail "root"                is_safe_target "/"
assert_fail "\$HOME itself"       is_safe_target "$HOME"
assert_fail "\$HOME with slash"   is_safe_target "$HOME/"
assert_fail "resolved \$HOME"     is_safe_target "$HOME_P"
assert_fail "resolved \$HOME/"    is_safe_target "$HOME_P/"

# Relative paths: cdm can only reason about absolute ones, and a relative path
# would resolve against whatever cwd the caller happened to be in.
assert_fail "bare relative path"  is_safe_target "Library/Caches"
assert_fail "dot-relative path"   is_safe_target "./Library/Caches"

# ".." is refused lexically, anywhere in the string — cheaper and stricter than
# reasoning about where it would land.
assert_fail "parent traversal"    is_safe_target "$HOME/Library/../../etc"
assert_fail ".. even when it stays home" \
                                  is_safe_target "$HOME/Library/Caches/../Caches"

assert_fail "nonexistent path"    is_safe_target "$HOME/Library/Caches/nope-xyzzy"

# ---- refuses: outside the home tree ----------------------------------------

assert_fail "system dir"          is_safe_target "/etc"
assert_fail "another user's home" is_safe_target "/Users/somebody-else"
assert_fail "outside temp dir"    is_safe_target "$OUTSIDE"
assert_fail "file outside home"   is_safe_target "$OUTSIDE/precious"

# ---- refuses: the protected set --------------------------------------------

for d in Documents Desktop Downloads Pictures Movies Music .ssh .gnupg \
         "Library/Mobile Documents"; do
    assert_fail "protected: ~/$d" is_safe_target "$HOME/$d"
done

# Children of the protected set are refused too, not just the roots themselves.
mkdir -p "$HOME/Documents/work" "$HOME/.ssh/keys" "$HOME/Library/Mobile Documents/x"
assert_fail "protected child: ~/Documents/work" is_safe_target "$HOME/Documents/work"
assert_fail "protected child: ~/.ssh/keys"      is_safe_target "$HOME/.ssh/keys"
assert_fail "protected child: iCloud Drive" \
    is_safe_target "$HOME/Library/Mobile Documents/x"

# ---- symlinks ---------------------------------------------------------------
#
# The crown jewel. "$HOME/escape-hatch/precious" passes every lexical check —
# it is absolute, has no "..", exists, and starts with "$HOME/" — and is still
# outside the real home. Only resolving the parent with `cd -P` catches it.

assert_fail "symlinked component escapes home" \
    is_safe_target "$HOME/escape-hatch/precious"

# The mirror image, and the one case that proves the LEXICAL check earns its
# keep. "$OUTSIDE/into-home/com.example.app" resolves physically to a real cache
# dir inside the home tree, so the parent-resolution check alone would accept
# it. Only the lexical "must start with $HOME/" test refuses it. Drop that check
# and this is the assertion that notices — cdm requires BOTH, and this is why.
assert_fail "a path outside home that resolves into it" \
    is_safe_target "$OUTSIDE/into-home/com.example.app"

# But the symlink as the FINAL component is reachable, and that is deliberate:
# is_safe_target resolves the parent, not the path itself. Every method deletes
# the link rather than following it, so the target is never touched — verified
# on macOS below, because all three depend on tool defaults that are easy to
# "fix" into data loss:
#   rm -rf <symlink>       removes the link; POSIX rm never follows one.
#   mv <symlink> <dest>    moves the link.
#   chmod -R u+w <symlink> defaults to -P on macOS, so it follows nothing —
#                          adding -L or -H here would chmod the whole target.
assert_ok "a symlink in \$HOME is itself reachable" \
    is_safe_target "$HOME/escape-hatch"

chmod -R u+w "$HOME/escape-hatch" 2>/dev/null
assert_ok "chmod -R through a symlink leaves the target alone" \
    test -e "$OUTSIDE/precious"

rm -rf "$HOME/escape-hatch"
assert_ok "deleting a symlink leaves its target alone" test -e "$OUTSIDE/precious"
assert_ok "deleting a symlink removes the link" \
    test ! -L "$HOME/escape-hatch"

test_summary
