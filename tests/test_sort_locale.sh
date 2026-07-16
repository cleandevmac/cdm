#!/bin/bash
# `sort -u` must not be left to the user's collation.
#
# BSD sort's -u drops a line that compares EQUAL to the line before it, and
# "equal" means strcoll, not bytes. cdm pins LC_CTYPE and deliberately leaves
# LC_COLLATE to the user (docs/DESIGN.md#locale-pin), so every unpinned
# `sort -u` in cdm decides what to discard using a comparison the user's
# environment chose. Three of the four sites feed a decision about deleting
# files. see docs/DESIGN.md#sort-u-collation
#
# The mechanism, established by experiment rather than assumed (it is easy to
# get wrong, and the plausible guesses are both false — see the design note):
# every character MISSING from the locale's collation table collates as one
# shared weight, so two such characters are indistinguishable from each other,
# though never from a plain ASCII line. "café" and "cafè" spelled NFD are
# "cafe"+U+0301 and "cafe"+U+0300 — same base letters, and the two combining
# marks are both uncollatable, hence both the same weight. They compare equal
# and `sort -u` keeps one. Two real, differently-named directories; one of them
# silently ceases to exist as far as the rest of the run is concerned.
#
# NFD is not a curiosity here: it is what git hands back with
# core.precomposeunicode=false, and what arrives from Linux-authored repos,
# rsync, and zip archives. It does not need APFS to normalise anything.
#
# The locale is set by `export` inside a ( ) subshell, and BOTH halves matter:
#
#   * export, because the collation under test is `sort`'s, not bash's. A bare
#     `LC_ALL=x` assignment is a shell variable — an exec'd child never sees it,
#     so the hostile locale would not apply, every assertion below would measure
#     C, and the file would pass while testing nothing. This is the same trap
#     in_locale (tests/lib.sh) is built around, and it is why that helper both
#     exports AND assigns: the export is what reaches a forked child, which is
#     what this file and test_helpers.sh's awk need, while the assignment is what
#     re-inits THIS shell's own collation, which is what a caller testing a bash
#     pattern match (is_ascii, looks_like_bundle_id) needs. The `LC_ALL=x cmd`
#     prefix form would work on `sort` directly, but the sorts under test are
#     buried inside cdm functions, so what we need is the function's children to
#     inherit the locale.
#
#     These stay local rather than calling in_locale because they are the file's
#     PREMISE checks — they assert that the hostile collation is hostile and that
#     an export reaches a child. Routing them through the helper whose contract
#     they exist to prove would be circular.
#   * the ( ), because assert_* run their command in the CURRENT shell, so an
#     unwrapped export would leak into every later assertion in this file.

. "$(dirname "$0")/lib.sh"

# Three distinct filenames: café, cafè, cafë — each spelled NFD, i.e. an ASCII
# base plus a combining mark. Byte-distinct, and asserted so below.
NFD_ACUTE=$'cafe\xcc\x81'
NFD_GRAVE=$'cafe\xcc\x80'
NFD_UML=$'cafe\xcc\x88'

# ---- premise ---------------------------------------------------------------
#
# bash and sort both fall back to C SILENTLY on an unknown locale — no
# diagnostic, exit 0 — so if en_US.UTF-8 ever stopped resolving on this machine,
# everything below would pass vacuously under C and prove nothing. These touch no
# cdm code; they assert only that the hostile collation really is hostile, and
# that the export actually reaches a child. If they fail, this file has lost its
# teeth: find out why rather than deleting it.

assert_eq 3 "$(printf '%s\n%s\n%s\n' "$NFD_ACUTE" "$NFD_GRAVE" "$NFD_UML" \
    | LC_ALL=C sort -u | wc -l | tr -d ' ')" \
    'premise: the three NFD names are byte-distinct'

raw_sort_u() { ( export LC_ALL="$1"
    printf '%s\n%s\n%s\n' "$NFD_ACUTE" "$NFD_GRAVE" "$NFD_UML" | sort -u | wc -l | tr -d ' '); }

assert_eq 1 "$(raw_sort_u en_US.UTF-8)" \
    'premise: under en_US collation an unpinned `sort -u` destroys 2 of the 3'
assert_eq 3 "$(raw_sort_u C)" \
    'premise: under C collation all three survive'

# ---- the behaviour ---------------------------------------------------------
#
# flush_project_category is the one of the four sites reachable as a unit: it
# takes its item names as an argument, and parks the joined "what's inside" blurb
# in CAT_SUMMARY. The other three sites are covered by the static guard below —
# build_installed_set shells out to lsregister and mdfind, so it cannot run here.

# summary_entries <locale> <names> — the number of comma-joined names that
# survive into the category summary.
summary_entries() {
    ( export LC_ALL="$1"
      N=0; CAT_SUMMARY=()
      flush_project_category "$HOME/proj" "$HOME/proj/x" "rm" "$2" >/dev/null 2>&1
      printf '%s' "${CAT_SUMMARY[0]}" | awk -F', ' '{ print NF }' )
}

NAMES=$(printf '%s\n%s\n%s' "$NFD_ACUTE" "$NFD_GRAVE" "$NFD_UML")

assert_eq 3 "$(summary_entries en_US.UTF-8 "$NAMES")" \
    'summary keeps all three NFD names under a hostile collation'
assert_eq 3 "$(summary_entries C "$NAMES")" \
    'summary keeps all three NFD names under C'
assert_eq 2 "$(summary_entries en_US.UTF-8 "$(printf 'node_modules\ntarget\nnode_modules')")" \
    'summary still de-duplicates genuinely identical names'

# ---- the static guard ------------------------------------------------------
#
# The three remaining sites need a scan of the real filesystem (or lsregister) to
# reach, so they are pinned by inspection rather than exercised. This is the same
# approach, and the same comment-stripping caveat, as tests/test_portability.sh:
# a guard that matches its own documentation cannot fire, so the grep runs over
# comment-stripped source. Counting occurrences rather than matching lines means
# a second, unpinned `sort -u` sharing a line with a pinned one cannot hide.

code_lines() {
    grep -n -v '^[[:space:]]*#' "$CDM_BIN" \
        | sed -e 's/[[:space:]]#[[:space:]].*$//' -e 's/[[:space:]]#$//'
}

n_sort_u=$(code_lines | grep -o -- 'sort -u' | wc -l | tr -d ' ')
n_pinned=$(code_lines | grep -o -- 'LC_ALL=C sort -u' | wc -l | tr -d ' ')

# If this trips, the guard is asserting nothing: the sites were renamed away.
assert_eq 4 "$n_sort_u" 'guard premise: cdm still has the four `sort -u` sites'
assert_eq "$n_sort_u" "$n_pinned" 'every `sort -u` in cdm pins LC_ALL=C'

test_summary
