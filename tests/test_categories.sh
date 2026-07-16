#!/bin/bash
# The category model (cdm's category-model section) and the passes that reorder
# it (prune_zero and sort_by_size).
#
# macOS ships bash 3.2, which has no associative arrays, so a category is not an
# object — it is one index shared across ten arrays: CAT_ICON, CAT_NAME,
# CAT_DESC, CAT_METHOD, CAT_DEFAULT, CAT_PATHS, CAT_KB, CAT_SEL, CAT_PMETHOD and
# CAT_SUMMARY, with N as the count. The invariant is ALIGNMENT: after any
# operation, index i still names the same category in all ten.
#
# Nothing enforces that. prune_zero's copy block and sort_by_size's two each
# hand-copy all ten arrays, so adding an eleventh array and forgetting it in one
# of those three copy blocks desynchronizes the model silently: no error, no
# crash, just a row that renders one category's name beside another's size —
# and, since CAT_PATHS is what clean_selected deletes, potentially deletes the
# paths of a category the user never selected.
#
# Which is why the assertions below never check a single column. The fixtures
# make every field carry its row's tag ("name-B", "desc-B", "/paths/B", ...) and
# `row` prints all ten joined, so an assertion fails whenever any one array is
# left behind. Two traps this defends against:
#
#   * "is CAT_KB sorted descending?" is a vacuous test of sort_by_size. Permute
#     CAT_KB and forget CAT_NAME and the KB column is still perfectly sorted —
#     it is the names beside it that are wrong.
#   * prune_zero compacts in place and never shrinks the arrays, so a forgotten
#     array does not go empty, it goes STALE — index 0 keeps the value it always
#     had. Every fixture below therefore drops row 0, so no surviving row lands
#     back on its own index (every kept row moves) and a stale array cannot hold
#     a coincidentally-correct value.

. "$(dirname "$0")/lib.sh"

# ---- helpers ---------------------------------------------------------------

# Mirrors the reset at the top of load_patterns(). Each fixture starts from
# empty so a previous fixture's tail can never satisfy an assertion.
reset_cats() {
    CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=()
    CAT_DEFAULT=(); CAT_PATHS=(); CAT_KB=(); CAT_SEL=()
    CAT_PMETHOD=(); CAT_SUMMARY=(); N=0
}

# row <i> — all ten fields of category <i>, joined. The whole point: an
# assertion on this fails if ANY single array is misaligned, not just CAT_KB.
row() {
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s' \
        "${CAT_ICON[$1]}" "${CAT_NAME[$1]}" "${CAT_DESC[$1]}" \
        "${CAT_METHOD[$1]}" "${CAT_DEFAULT[$1]}" "${CAT_PATHS[$1]}" \
        "${CAT_KB[$1]}" "${CAT_SEL[$1]}" "${CAT_PMETHOD[$1]}" "${CAT_SUMMARY[$1]}"
}

# want_row <tag> <kb> <method> <default> <sel> — the same ten fields as `row`
# would print them for a category built by mkcat. Kept in lockstep with mkcat.
want_row() {
    printf 'i%s|name-%s|desc-%s|%s|%s|/paths/%s|%s|%s|pm-%s|sum-%s' \
        "$1" "$1" "$1" "$3" "$4" "$1" "$2" "$5" "$1" "$1"
}

# mkcat <tag> <kb> <method> <default> <sel> — one category whose every field is
# distinct and derivable from its tag. add_category owns CAT_KB/CAT_SEL/
# CAT_SUMMARY (0/default/empty), so the fixture overwrites those three after.
mkcat() {
    add_category "i$1" "name-$1" "desc-$1" "$3" "$4" "/paths/$1" "pm-$1"
    CAT_KB[$((N - 1))]="$2"
    CAT_SEL[$((N - 1))]="$5"
    CAT_SUMMARY[$((N - 1))]="sum-$1"
}

# names — the CAT_NAME column, in index order. Reported alongside `row` checks
# so a failure says "the order is wrong" rather than just "row 2 differs".
names() {
    local i out=""
    for i in $(cat_indices); do out="${out:+$out }${CAT_NAME[$i]}"; done
    printf '%s' "$out"
}

# ---- add_category ----------------------------------------------------------

reset_cats
assert_eq "0" "$N" "N starts at 0"

add_category "ICON0" "NAME0" "DESC0" "rm" "1" "/path/0" "PM0"
assert_eq "1" "$N" "add_category increments N"
assert_eq "ICON0|NAME0|DESC0|rm|1|/path/0|0|1|PM0|" "$(row 0)" \
    "every field of the first category lands at index 0"

# CAT_SEL is seeded from the default, not from a literal: this is what makes a
# category arrive pre-selected, and what select_safe later restores to.
add_category "ICON1" "NAME1" "DESC1" "trash" "0" "/path/1" "PM1"
assert_eq "2" "$N" "add_category appends rather than overwriting"
assert_eq "ICON1|NAME1|DESC1|trash|0|/path/1|0|0|PM1|" "$(row 1)" \
    "the second category lands at index 1, seeded unselected from default=0"
assert_eq "ICON0|NAME0|DESC0|rm|1|/path/0|0|1|PM0|" "$(row 0)" \
    "appending leaves the earlier category untouched"

# An EMPTY icon must not shift the other fields. Every field is a distinct
# positional parameter, so a caller that loses the empty argument (an unquoted
# expansion anywhere upstream) would slide name into icon, desc into name, and
# so on — and the row would still look plausible.
add_category "" "NAME2" "DESC2" "rm" "1" "/path/2" "PM2"
assert_eq "3" "$N" "an empty icon still counts as a category"
assert_eq "|NAME2|DESC2|rm|1|/path/2|0|1|PM2|" "$(row 2)" \
    "an empty icon does not shift name/desc/method into the wrong columns"
assert_eq "" "${CAT_ICON[2]}" "the empty icon is stored as empty, not as the name"
assert_eq "NAME2" "${CAT_NAME[2]}" "name stays in CAT_NAME when the icon is empty"

# The 7th argument is optional (only "project" categories pass per-path methods).
add_category "ICON3" "NAME3" "DESC3" "rm" "0" "/path/3"
assert_eq "ICON3|NAME3|DESC3|rm|0|/path/3|0|0||" "$(row 3)" \
    "an omitted pmethods argument defaults CAT_PMETHOD to empty"

assert_eq "NAME0 NAME1 NAME2 NAME3" "$(names)" "cat_indices walks 0..N-1 in order"

# ---- prune_zero ------------------------------------------------------------
#
# Six rows; three survive on size and one on the emptytrash exemption. Row 0 is
# a zero, so every surviving row moves to a lower index (1->0, 3->1, 4->2,
# 5->3) and prune_zero's copy block is exercised for all ten arrays on all
# four rows. Fields vary independently — DEFAULT and SEL are deliberately not
# equal to each other, and the methods differ between adjacent survivors — so
# no forgotten array can hold a right-looking stale value.

reset_cats
mkcat A 0    rm         1 0
mkcat B 100  rm         0 1
mkcat C 0    trash      1 0
mkcat D 50   trash      1 0
mkcat E 0    emptytrash 0 1
mkcat F 200  rm         1 0
assert_eq "6" "$N" "fixture built six categories"

prune_zero

assert_eq "4" "$N" "prune_zero drops the two zero-size categories"
assert_eq "name-B name-D name-E name-F" "$(names)" \
    "survivors compact to the front in their original relative order"

# The alignment assertions. Each compares all ten fields at once, so forgetting
# any one array in the copy block fails here.
assert_eq "$(want_row B 100 rm 0 1)"         "$(row 0)" \
    "prune_zero: row B keeps all ten of its own fields at its new index"
assert_eq "$(want_row D 50 trash 1 0)"       "$(row 1)" \
    "prune_zero: row D keeps all ten of its own fields at its new index"
assert_eq "$(want_row E 0 emptytrash 0 1)"   "$(row 2)" \
    "prune_zero: row E keeps all ten of its own fields at its new index"
assert_eq "$(want_row F 200 rm 1 0)"         "$(row 3)" \
    "prune_zero: row F keeps all ten of its own fields at its new index"

# The emptytrash exemption in prune_zero is the one reason a zero-KB row lives:
# ~/.Trash reports whatever size it likes and the row must stay offerable.
assert_eq "name-E" "${CAT_NAME[2]}" \
    "a zero-size emptytrash category survives the prune"
assert_eq "emptytrash" "${CAT_METHOD[2]}" \
    "the surviving zero-size row is the emptytrash one, not a mis-copied neighbour"

# Nothing to prune: prune_zero's w == r fast path must leave the list alone.
reset_cats
mkcat G 10 rm    1 1
mkcat H 20 trash 0 0
prune_zero
assert_eq "2" "$N" "prune_zero keeps every category when none is zero"
assert_eq "$(want_row G 10 rm 1 1)"    "$(row 0)" \
    "prune_zero: the no-op path leaves row G intact"
assert_eq "$(want_row H 20 trash 0 0)" "$(row 1)" \
    "prune_zero: the no-op path leaves row H intact"

# All zeroes: N must reach 0, not stay put.
reset_cats
mkcat I 0 rm    1 1
mkcat J 0 trash 0 0
prune_zero
assert_eq "0" "$N" "prune_zero empties the list when every category is zero"

reset_cats
prune_zero
assert_eq "0" "$N" "prune_zero on an empty list is a no-op"

# ---- sort_by_size ----------------------------------------------------------
#
# Built deliberately out of KB order, with a tie in the middle. Expected order
# is Q(500) R(500) T(300) P(90) S(0): descending, and Q before R because
# `sort -s` keeps equal sizes in rules-file order — drop the -s and BSD sort's
# last-resort whole-line comparison, itself reversed by -r, puts R first.
#
# P is 90, not some round 10: the sort key is a NUMBER, and a fixture of
# 10/500/300/0 sorts to the same sequence whether `sort` is told -rn or plain
# -r, so it cannot tell a numeric sort from a lexical one. 90 is the cheapest
# value that disagrees — lexically "90" is the largest string here and would
# land P at the top, which is exactly the bug (a 90KB row pushed above a 500KB
# one) that -n exists to prevent.
#
# Note every row moves: P 0->3, Q 1->0, R 2->1, S 3->4, T 4->2. So an array
# that is permuted into the temporaries but not written back (or written back
# unpermuted) is wrong at every index, not just some.

reset_cats
mkcat P 90  rm         1 0
mkcat Q 500 trash      0 1
mkcat R 500 rm         1 1
mkcat S 0   emptytrash 0 0
mkcat T 300 trash      1 0

sort_by_size

assert_eq "5" "$N" "sort_by_size does not change the category count"
assert_eq "name-Q name-R name-T name-P name-S" "$(names)" \
    "sort_by_size orders biggest-first and keeps the 500KB tie in rules order"
assert_eq "500 500 300 90 0" \
    "$(for i in $(cat_indices); do printf '%s ' "${CAT_KB[$i]}"; done | sed 's/ $//')" \
    "CAT_KB descends numerically — 90 sorts below 300, not above it as a string"

# The assertions that matter: a sort that permutes CAT_KB but forgets any other
# array leaves the KB column above perfectly sorted and these wrong.
assert_eq "$(want_row Q 500 trash 0 1)"    "$(row 0)" \
    "sort_by_size: row Q carries all ten of its fields to the top"
assert_eq "$(want_row R 500 rm 1 1)"       "$(row 1)" \
    "sort_by_size: row R carries all ten of its fields to its tied slot"
assert_eq "$(want_row T 300 trash 1 0)"    "$(row 2)" \
    "sort_by_size: row T carries all ten of its fields"
assert_eq "$(want_row P 90 rm 1 0)"        "$(row 3)" \
    "sort_by_size: row P carries all ten of its fields"
assert_eq "$(want_row S 0 emptytrash 0 0)" "$(row 4)" \
    "sort_by_size: row S carries all ten of its fields to the bottom"

# Sorting an already-sorted list must be idempotent, ties included.
sort_by_size
assert_eq "name-Q name-R name-T name-P name-S" "$(names)" \
    "sort_by_size is idempotent — a second pass does not reshuffle the tie"
assert_eq "$(want_row R 500 rm 1 1)" "$(row 1)" \
    "sort_by_size: the second pass keeps row R aligned"

reset_cats
sort_by_size
assert_eq "0" "$N" "sort_by_size on an empty list is a no-op"

# ---- selected_count / selected_kb ------------------------------------------
#
# The sizes are chosen so the three plausible wrong answers are all distinct
# from the right one: summing every row gives 1130, summing none gives 0, and
# summing the unselected gives 1007. The right answer is 123.

reset_cats
mkcat U 100  rm    1 1
mkcat V 7    trash 0 0
mkcat W 20   rm    0 1
mkcat X 1000 trash 1 0
mkcat Y 3    rm    1 1

assert_eq "3"   "$(selected_count)" "selected_count counts only the selected rows"
assert_eq "123" "$(selected_kb)"    "selected_kb sums only the selected rows"

# CAT_SEL is compared as the string "1" in selected_count, so anything else is
# unselected — including values that are merely truthy-looking.
CAT_SEL[1]="0"
assert_eq "3"   "$(selected_count)" "an already-unselected row stays uncounted"
CAT_SEL[3]="1"
assert_eq "4"   "$(selected_count)" "selecting a row raises the count"
assert_eq "1123" "$(selected_kb)"   "selecting the 1000KB row raises the total by 1000"

reset_cats
assert_eq "0" "$(selected_count)" "selected_count is 0 on an empty list"
assert_eq "0" "$(selected_kb)"    "selected_kb is 0 on an empty list"

# ---- toggle_all / select_safe ----------------------------------------------
#
# The defaults are mixed (1,0,0,1,1) precisely so select_safe cannot be faked by
# a function that just sets everything to 1 — or to 0.

reset_cats
mkcat AA 100  rm         1 0
mkcat BB 7    trash      0 1
mkcat CC 20   rm         0 1
mkcat DD 1000 trash      1 0
mkcat EE 3    emptytrash 1 1

toggle_all 1
assert_eq "5"    "$(selected_count)" "toggle_all 1 selects every category"
assert_eq "1130" "$(selected_kb)"    "toggle_all 1 makes selected_kb the full total"

toggle_all 0
assert_eq "0" "$(selected_count)" "toggle_all 0 deselects every category"
assert_eq "0" "$(selected_kb)"    "toggle_all 0 makes selected_kb zero"

# From all-deselected back to the rules' own defaults: 1,0,0,1,1 -> AA,DD,EE.
select_safe
assert_eq "3" "$(selected_count)" "select_safe restores CAT_SEL from CAT_DEFAULT"
assert_eq "1103" "$(selected_kb)" "select_safe selects exactly the default rows"
assert_eq "1|0|0|1|1" \
    "$(printf '%s|%s|%s|%s|%s' "${CAT_SEL[0]}" "${CAT_SEL[1]}" "${CAT_SEL[2]}" \
        "${CAT_SEL[3]}" "${CAT_SEL[4]}")" \
    "select_safe restores each row's own default, not a blanket value"

# And from all-selected, so a select_safe that only ever turns rows ON is caught.
toggle_all 1
select_safe
assert_eq "3" "$(selected_count)" "select_safe deselects rows whose default is 0"
assert_eq "1|0|0|1|1" \
    "$(printf '%s|%s|%s|%s|%s' "${CAT_SEL[0]}" "${CAT_SEL[1]}" "${CAT_SEL[2]}" \
        "${CAT_SEL[3]}" "${CAT_SEL[4]}")" \
    "select_safe from all-selected still lands on the defaults"

# select_safe copies DEFAULT -> SEL and never the reverse; a swapped assignment
# would pass every count assertion above while quietly destroying the defaults.
toggle_all 0
select_safe
assert_eq "1|0|0|1|1" \
    "$(printf '%s|%s|%s|%s|%s' "${CAT_DEFAULT[0]}" "${CAT_DEFAULT[1]}" \
        "${CAT_DEFAULT[2]}" "${CAT_DEFAULT[3]}" "${CAT_DEFAULT[4]}")" \
    "select_safe leaves CAT_DEFAULT itself untouched"

# Neither function may disturb any other column.
assert_eq "$(want_row AA 100 rm 1 1)" "$(row 0)" \
    "toggle_all/select_safe touch CAT_SEL and nothing else"

test_summary
