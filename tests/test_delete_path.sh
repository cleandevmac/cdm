#!/bin/bash
# delete_path(), move_to_trash() and empty_trash() — the three functions that
# actually destroy data, tested for real against fixtures in the sandbox home
# rather than mocked.
#
# What makes this file subtle is that almost every assertion here has a vacuous
# twin, and the vacuous one reads identically:
#
#   * delete_path returns 0 for THREE different reasons — it deleted the thing,
#     its existence check found the thing already gone, or the method fell off
#     the end of the case. And "rm" returns 0 even when `rm -rf` failed, because
#     that branch discards rm's exit status. So an exit code proves nothing on
#     its own: every claim below is pinned by looking at the filesystem
#     afterwards.
#   * the refusal test is the mirror trap, and it is the reason every unsafe
#     fixture here is created before it is refused. delete_path's existence
#     check runs BEFORE its is_safe_target gate, so a refusal asserted on a path
#     that merely does not exist never reaches the gate at all — and would keep
#     "passing" with the whole is_safe_target call deleted. Both unsafe fixtures
#     are therefore made to exist first and checked to STILL exist afterwards.
#     Proving the file survived is the assertion; the exit code is the footnote.
#   * "recoverable" is a promise about data, not about a rename. Trashing is
#     checked by reading the payload back out of ~/.Trash, so a move_to_trash
#     that lost the contents and left an empty directory behind would fail.
#   * `date` is stubbed for the collision block only. move_to_trash's dedup name
#     is built from a timestamp, so the third collision only reaches that
#     block's `-${n}` suffix loop if it lands in the same SECOND as the second
#     one. Left to the wall clock that is a coin flip that passes locally and
#     flakes in CI; pinning the clock makes the loop run every time.

. "$(dirname "$0")/lib.sh"

# ---- fixtures --------------------------------------------------------------

# A real directory outside the sandbox home, standing in for everything cdm must
# never touch. Nothing below references a real user path.
OUTSIDE=$(mktemp -d "${TMPDIR:-/tmp}/cdm-test-outside.XXXXXX") || exit 1
: > "$OUTSIDE/keepme"
mkdir -p "$OUTSIDE/linktarget" || exit 1
: > "$OUTSIDE/linktarget/precious"
# 0400 so that a chmod which wrongly followed a symlink into this tree would
# leave a visible mark. See the symlink section.
chmod 0400 "$OUTSIDE/linktarget/precious"

_delete_path_cleanup() {
    # The read-only fixtures below would otherwise defeat the sandbox's own
    # rm -rf. $HOME here is the mktemp'd test home, never a real one.
    chmod -R u+w "$HOME" 2>/dev/null
    chmod -R u+w "$OUTSIDE" 2>/dev/null
    rm -rf "$OUTSIDE" 2>/dev/null
    _cdm_test_cleanup
}
trap _delete_path_cleanup EXIT

mkdir -p "$HOME/Library/Caches" || exit 1

# ---- empty_trash with no Trash at all --------------------------------------
#
# Ordering: this has to run before anything trashes a fixture, because it is the
# only moment the sandbox home has no ~/.Trash. move_to_trash mkdir -p's one on
# its way in, and after that this branch is unreachable.

assert_ok "empty_trash with no ~/.Trash is a no-op" empty_trash
assert_ok "empty_trash did not conjure a ~/.Trash" test ! -d "$HOME/.Trash"

# ---- delete_path rm: permanent ---------------------------------------------

mkdir -p "$HOME/Library/Caches/com.example.app/inner" || exit 1
: > "$HOME/Library/Caches/com.example.app/inner/blob"

assert_ok "rm a cache dir under \$HOME" \
    delete_path rm "$HOME/Library/Caches/com.example.app"
assert_ok "the dir is actually gone" \
    test ! -e "$HOME/Library/Caches/com.example.app"
# "rm" means permanent. If this method ever quietly became a trash, the caller's
# consent (print_plan calls it a delete) would be a lie — and ~/.Trash would grow
# by the size of every cache cdm claims to have freed.
assert_ok "rm did not route through the Trash" \
    test ! -e "$HOME/.Trash/com.example.app"

# ---- delete_path trash: recoverable ----------------------------------------

mkdir -p "$HOME/Library/Caches/trashme" || exit 1
echo "payload-abc" > "$HOME/Library/Caches/trashme/data.txt"

assert_ok "trash a cache dir under \$HOME" \
    delete_path trash "$HOME/Library/Caches/trashme"
assert_ok "the dir left its original location" \
    test ! -e "$HOME/Library/Caches/trashme"
assert_ok "the dir arrived in ~/.Trash" test -d "$HOME/.Trash/trashme"
# The whole point of `trash` over `rm`. A move that dropped the payload would
# still satisfy both assertions above.
assert_eq "payload-abc" "$(cat "$HOME/.Trash/trashme/data.txt" 2>/dev/null)" \
    "the trashed data is still readable — this is what 'recoverable' means"

# ---- move_to_trash: collisions (its dedup block) ----------------------------
#
# Three different directories, one shared basename. Cache dirs collide like this
# constantly (every repo has a `node_modules`), and the second one landing on top
# of the first would silently destroy data the user was told was recoverable.

date() { echo "20200101-000000"; }   # pin the dedup timestamp; see header.

for d in a b c; do
    mkdir -p "$HOME/Library/Caches/$d/dup" || exit 1
    : > "$HOME/Library/Caches/$d/dup/marker-$d"
done

assert_ok "trash the 1st dup"  delete_path trash "$HOME/Library/Caches/a/dup"
assert_ok "trash the 2nd dup"  delete_path trash "$HOME/Library/Caches/b/dup"
assert_ok "trash the 3rd dup"  delete_path trash "$HOME/Library/Caches/c/dup"

# Each is identified by its own marker file, so an entry that exists under the
# right name but holds the wrong (or nested) payload cannot pass.
assert_ok "1st dup keeps the plain name" \
    test -f "$HOME/.Trash/dup/marker-a"
assert_ok "2nd dup is parked beside it, not on top of it" \
    test -f "$HOME/.Trash/dup 20200101-000000/marker-b"
assert_ok "3rd dup takes the -1 suffix from the dedup loop" \
    test -f "$HOME/.Trash/dup 20200101-000000-1/marker-c"

# Belt and braces on the above: exactly three entries, so a fourth name or a
# swallowed one shows up here too.
count_dups() {
    local n=0 e
    for e in "$HOME"/.Trash/dup*; do
        [ -e "$e" ] && n=$((n + 1))
    done
    echo "$n"
}
assert_eq "3" "$(count_dups)" "all three dups survive in the Trash"

unset -f date

# ---- move_to_trash reports a move it could not make (its mv guards) ---------
#
# A trash is a rename, and a rename needs write permission on the SOURCE's parent
# — which a read-only cache tree does not give. move_to_trash guards this twice,
# on mv's status and again by confirming the source is gone, and the pair matters
# more than either half: reporting a trash that never happened would tell the
# user their data is recoverable from ~/.Trash when it is not there at all.
#
# The pair is all this can pin, and deliberately so. Dropping EITHER guard alone
# is an equivalent mutant — no real mv both fails and removes the source, nor
# succeeds and leaves it, so with the other guard still standing no input tells
# the two apart. Dropping both IS caught, which is the bug worth catching.

mkdir -p "$HOME/Library/Caches/locked/victim" || exit 1
: > "$HOME/Library/Caches/locked/victim/data"
chmod 0500 "$HOME/Library/Caches/locked"

assert_fail "move_to_trash reports failure when the mv cannot happen" \
    move_to_trash "$HOME/Library/Caches/locked/victim"
assert_ok "...and the data it could not move is untouched" \
    test -f "$HOME/Library/Caches/locked/victim/data"
assert_ok "...and nothing was reported into the Trash" test ! -e "$HOME/.Trash/victim"

chmod -R u+w "$HOME/Library/Caches/locked"

# ---- delete_path on a path that is already gone (its existence check) -------
#
# Not an error: categories overlap, so an earlier one in the same run may have
# already removed this. Returning 1 here would make a clean report failures for
# work that succeeded.

assert_ok "rm of a nonexistent path is success" \
    delete_path rm "$HOME/Library/Caches/nope-xyzzy"
assert_ok "trash of a nonexistent path is success" \
    delete_path trash "$HOME/Library/Caches/nope-xyzzy"
assert_ok "rmforce of a nonexistent path is success" \
    delete_path rmforce "$HOME/Library/Caches/nope-xyzzy"
assert_ok "a nonexistent path is not resurrected in the Trash" \
    test ! -e "$HOME/.Trash/nope-xyzzy"

# ---- delete_path REFUSES an unsafe target (its is_safe_target gate) ---------
#
# The load-bearing test in this file: the join between the gate and the deleter.
# is_safe_target can be perfect and it buys nothing if delete_path forgets to
# call it. Every fixture here exists — a refusal on an absent path would be
# indistinguishable from the "already gone" success above.

assert_fail "rm refuses a target outside the home tree" \
    delete_path rm "$OUTSIDE/keepme"
assert_ok "...and the file outside the home tree IS STILL THERE" \
    test -f "$OUTSIDE/keepme"

assert_fail "trash refuses a target outside the home tree" \
    delete_path trash "$OUTSIDE/keepme"
assert_ok "...and it was not moved into the Trash either" \
    test ! -e "$HOME/.Trash/keepme"
assert_ok "...and it is still outside the home tree" test -f "$OUTSIDE/keepme"

assert_fail "rmforce refuses a target outside the home tree" \
    delete_path rmforce "$OUTSIDE/keepme"
assert_ok "...and rmforce's chmod -R did not run on it" test -f "$OUTSIDE/keepme"

# The protected set, reached through delete_path rather than directly: a rule
# file that pointed a category at ~/Documents must not be able to fire.
mkdir -p "$HOME/Documents/work" || exit 1
: > "$HOME/Documents/work/thesis"
assert_fail "rm refuses the protected set" delete_path rm "$HOME/Documents/work"
assert_ok "...and the protected file IS STILL THERE" \
    test -f "$HOME/Documents/work/thesis"

# $HOME itself, the worst case a wildcard could ever produce.
assert_fail "rm refuses \$HOME itself" delete_path rm "$HOME"
assert_ok "...and \$HOME is still populated" test -d "$HOME/Library/Caches"

# ---- rmforce vs rm on a read-only tree (delete_path's branches) -------------
#
# Go's module cache and Cargo's source cache ship 0500 directories. rm -rf cannot
# remove a file from a directory it cannot write to, so plain `rm` walks away
# having done nothing — while still printing "deleted" and returning 0, because
# rm's exit status is discarded. That silent no-op is the entire reason rmforce
# exists, so it is asserted rather than assumed.

mkdir -p "$HOME/Library/Caches/ro-plain/sub" || exit 1
: > "$HOME/Library/Caches/ro-plain/sub/file"
chmod 0400 "$HOME/Library/Caches/ro-plain/sub/file"
chmod 0500 "$HOME/Library/Caches/ro-plain/sub"
chmod 0500 "$HOME/Library/Caches/ro-plain"

assert_ok "rm on a read-only tree still reports success" \
    delete_path rm "$HOME/Library/Caches/ro-plain"
assert_ok "...but the read-only tree survives it — this is why rmforce exists" \
    test -f "$HOME/Library/Caches/ro-plain/sub/file"

mkdir -p "$HOME/Library/Caches/ro-force/sub" || exit 1
: > "$HOME/Library/Caches/ro-force/sub/file"
chmod 0400 "$HOME/Library/Caches/ro-force/sub/file"
chmod 0500 "$HOME/Library/Caches/ro-force/sub"
chmod 0500 "$HOME/Library/Caches/ro-force"

assert_ok "rmforce on a read-only tree" \
    delete_path rmforce "$HOME/Library/Caches/ro-force"
assert_ok "the read-only tree is gone" \
    test ! -e "$HOME/Library/Caches/ro-force"

chmod -R u+w "$HOME/Library/Caches/ro-plain" 2>/dev/null

# ---- symlinks under $HOME whose target is outside it ------------------------
#
# is_safe_target resolves a path's PARENT, so a symlink as the final component is
# reachable (see test_safe_target.sh) even when it points off the home tree. That
# is only safe because every method deletes the link instead of following it —
# which is a property of macOS tool defaults, not of anything cdm says. If those
# defaults were ever "fixed" (rm -rf trailing into the target, chmod -R gaining
# -L or -H) cdm would recursively chmod and delete a tree it never scanned.

ln -s "$OUTSIDE/linktarget" "$HOME/Library/Caches/link-rm"

assert_ok "rm a symlink pointing outside \$HOME" \
    delete_path rm "$HOME/Library/Caches/link-rm"
assert_ok "the link is gone" test ! -L "$HOME/Library/Caches/link-rm"
assert_ok "THE TARGET STILL EXISTS" test -f "$OUTSIDE/linktarget/precious"

ln -s "$OUTSIDE/linktarget" "$HOME/Library/Caches/link-rmforce"

assert_ok "rmforce a symlink pointing outside \$HOME" \
    delete_path rmforce "$HOME/Library/Caches/link-rmforce"
assert_ok "the link is gone" test ! -L "$HOME/Library/Caches/link-rmforce"
assert_ok "THE TARGET STILL EXISTS after rmforce" \
    test -f "$OUTSIDE/linktarget/precious"
# The one that pins chmod -R's -P default: had rmforce's chmod followed the link,
# it would have made the whole target tree u+w and this would read 600.
assert_eq "400" "$(stat -f %Lp "$OUTSIDE/linktarget/precious" 2>/dev/null)" \
    "rmforce's chmod -R did not follow the link into the target tree"

# ---- empty_trash (its glob loop) --------------------------------------------
#
# ~/.Trash still holds every fixture trashed above. The dotfile matters: the loop
# globs "$trash_dir"/* AND "$trash_dir"/.[!.]*, and dropping the second leaves
# hidden junk behind while reporting "Trash emptied."

: > "$HOME/.Trash/.hidden-junk"
assert_ok "the Trash is populated before emptying" test -d "$HOME/.Trash/trashme"

assert_ok "empty_trash" empty_trash
assert_ok "a trashed dir is gone" test ! -e "$HOME/.Trash/trashme"
assert_ok "the deduped collision entries are gone" \
    test ! -e "$HOME/.Trash/dup 20200101-000000"
assert_eq "0" "$(count_dups)" "every dup entry is gone from the Trash"
assert_ok "a dotfile in the Trash is gone too" test ! -e "$HOME/.Trash/.hidden-junk"
assert_ok "the Trash directory itself remains" test -d "$HOME/.Trash"

test_summary
