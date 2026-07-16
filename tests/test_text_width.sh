#!/bin/bash
# cdm's is_ascii / _cw / dwidth / clip_plain / shorten_left — the "measure in
# display columns, never in characters or bytes" machinery. Three different
# numbers are in play and the layout only ever wants the third: under bash 3.2
# `printf '%d' "'中"` answers -28 — the *lead byte* as a signed char, not the
# code point — so _cw's `v + 256` wrap is what every wide-character result below
# actually rests on, and deleting it silently makes the whole file measure 1 per
# character. The classification boundary is 0xE3/227, which puts an em dash
# (0xE2) at one column and Kana (0xE3) at two with one byte between them; both
# sides are pinned deliberately.
#
# The assertions are written as exact outputs *and* as the invariant that keeps
# a menu row from wrapping — dwidth(clip(s, max)) <= max — because those catch
# different mutations: an off-by-one in the budget still returns a plausible
# string, and only re-measuring the OUTPUT notices it is a column too wide.
#
# Note _cw/dwidth set the globals _CW/_DW rather than printing, so the cw/dw
# shims below exist purely to hand those globals to assert_eq.

. "$(dirname "$0")/lib.sh"

# ---- helpers ---------------------------------------------------------------

cw() { _cw "$1"; printf '%s' "$_CW"; }
dw() { dwidth "$1"; printf '%s' "$_DW"; }

# fits <clipper> <str> <max> — the load-bearing invariant, asserted by measuring
# the clipper's OUTPUT rather than by trusting its arithmetic. A wide character
# is indivisible: it either fits the remaining budget whole or must be dropped,
# and a clipper that lets one straddle the edge returns a string that renders
# wider than the row it was budgeted, wraps, and scrolls the frame on every
# repaint. render_menu() states this contract outright ("Both clippers return at
# most name_w *columns*, so this never goes negative").
fits() {
    local out
    out=$("$1" "$2" "$3") || return 1
    dwidth "$out"
    [ "$_DW" -le "$3" ]
}

# ---- _cw: one character to display columns ---------------------------------

assert_eq 1 "$(cw a)"  "ASCII letter is one column"
assert_eq 1 "$(cw ' ')" "ASCII space is one column"
assert_eq 1 "$(cw '~')" "ASCII tilde (top of the fast-path range) is one column"

# Below the 0xE3 boundary. These are the scripts the classifier deliberately
# leaves at one column, and each rests on the signed-char wrap: their lead bytes
# are 0xC3/0xCE/0xD0/0xE1, all of which printf reports negative.
assert_eq 1 "$(cw 'é')" "accented Latin é (lead 0xC3) is one column"
assert_eq 1 "$(cw 'ế')" "Vietnamese ế (lead 0xE1) is one column"
assert_eq 1 "$(cw 'α')" "Greek α (lead 0xCE) is one column"
assert_eq 1 "$(cw 'ж')" "Cyrillic ж (lead 0xD0) is one column"

# The boundary itself, from below: an em dash is U+2014, lead byte 0xE2 = 226,
# exactly one under the cutoff. Every rule desc carries one, so this is the
# character the whole cutoff has to get right.
assert_eq 1 "$(cw '—')" "em dash U+2014 (lead 0xE2 = 226) is one column"
assert_eq 1 "$(cw '…')" "ellipsis U+2026 (lead 0xE2) is one column — the clippers assume this"

# Documented known gap (docs/DESIGN.md#display-columns): U+2xxx symbols measure
# 1 but render 2. Pinned as-is so a future fix is a deliberate change rather
# than a surprise.
assert_eq 1 "$(cw '⚡')" "known gap: ⚡ U+26A1 measures 1 though it renders 2"

# At and above the boundary: two columns.
assert_eq 2 "$(cw 'ア')" "Katakana ア U+30A2 (lead 0xE3 = 227) is two columns — the cutoff"
assert_eq 2 "$(cw '中')" "CJK 中 (lead 0xE4) is two columns"
assert_eq 2 "$(cw '한')" "Hangul 한 (lead 0xED) is two columns"
assert_eq 2 "$(cw '😀')" "emoji (lead 0xF0) is two columns"

# ---- is_ascii: the guard all three fast paths hang on -----------------------
#
# This one shipped, so it is worth stating plainly. A bracket RANGE in a bash
# pattern is resolved by LC_COLLATE, so the original guard — `*[!\ -~]*` — was
# not the guard it looks like. Under any locale but C/POSIX — 284 of the 288 a
# stock macOS installs — the letters and digits collate above '~', leaving ' '
# through '~' a punctuation-only interval: the guard answered "not ASCII" for
# "abc" and all three fast paths were unreachable for very nearly every user. It
# failed OPEN, into a slower path that is correct, which is exactly why no
# assertion about output ever caught it.
#
# So these assertions pin their own locale instead of trusting the caller's. Two
# traps, both load-bearing:
#
#   * the locale must be set by ASSIGNMENT inside a ( ) subshell. The obvious
#     `LC_ALL=en_US.UTF-8 is_ascii abc` prefix form does NOT work — bash 3.2
#     re-runs setlocale when the variable is assigned, but not for the temporary
#     environment of a function call, so that form silently measures the
#     developer's own collation and passes for free.
#   * the ( ) is not optional for a second reason: assert_ok runs its command in
#     the CURRENT shell, so a bare assignment would leak into every later
#     assertion in this file.
in_locale() { ( LC_ALL="$1"; shift; "$@" ); }

# Premise check. bash falls back to C collation SILENTLY on an unknown locale —
# no diagnostic, exit 0 — so if en_US.UTF-8 ever stopped resolving, everything
# below would pass vacuously under C and prove nothing. This touches no cdm code;
# it asserts only that the hostile collation really is hostile. If it fails, this
# section has lost its teeth: find out why rather than deleting it.
range_has_a() { ( LC_ALL="$1"; case a in [\ -~]) printf 'yes' ;; *) printf 'no' ;; esac ); }
assert_eq no  "$(range_has_a en_US.UTF-8)" "premise: under en_US collation the range [ -~] excludes 'a'"
assert_eq yes "$(range_has_a C)"           "premise: under C collation it contains 'a'"

# The guard itself, under three arrivals that are all real and must all agree.
# They also isolate the two variables: en_US.UTF-8 is the hostile collation a
# Terminal exports, C is a bare ssh/launchd (byte ctype, C collation), and
# C.UTF-8 is the pair between them — UTF-8 ctype with C collation — which is the
# only one of the three that exercises bash's multibyte matcher against a C
# collation, and happens to be what this repo's own developer shell exports.
for loc in en_US.UTF-8 C C.UTF-8; do
    assert_ok   "is_ascii 'abcdef' under $loc"       in_locale "$loc" is_ascii 'abcdef'
    assert_ok   "is_ascii 'node_modules' under $loc" in_locale "$loc" is_ascii 'node_modules'
    assert_ok   "is_ascii 'Code Cache' under $loc"   in_locale "$loc" is_ascii 'Code Cache'
    assert_ok   "is_ascii '100%' under $loc"         in_locale "$loc" is_ascii '100%'
    assert_ok   "is_ascii ' a~ ' under $loc"         in_locale "$loc" is_ascii ' a~ '
    assert_fail "is_ascii '中文字' under $loc"        in_locale "$loc" is_ascii '中文字'
    assert_fail "is_ascii 'é' under $loc"            in_locale "$loc" is_ascii 'é'
    assert_fail "is_ascii '—' under $loc"            in_locale "$loc" is_ascii '—'
    assert_fail "is_ascii 'Tiếng-Việt' under $loc"   in_locale "$loc" is_ascii 'Tiếng-Việt'
done

# ---- dwidth: a whole string to display columns -----------------------------

assert_eq 0  "$(dw '')"           "empty string is zero columns"
assert_eq 3  "$(dw 'abc')"        "pure ASCII: fast path returns the length"
assert_eq 4  "$(dw ' a~ ')"       "fast path spans the whole printable ASCII range"
assert_eq 6  "$(dw '中文字')"      "3 CJK characters are 6 columns"
assert_eq 12 "$(dw 'プロジェクト')" "6 Kana characters are 12 columns"
assert_eq 4  "$(dw 'a中b')"       "mixed ASCII + CJK: 1 + 2 + 1"
assert_eq 5  "$(dw 'a%b中')"      "a % in the text is measured, never interpreted"

# The shipped bug, pinned: "Tiếng-Việt" is 10 characters and 10 display columns,
# but 14 bytes — so `printf '%-10s'`, which pads to bytes, gives it no padding at
# all. dwidth must answer 10, not 14.
assert_eq 10 "$(dw 'Tiếng-Việt')" "Tiếng-Việt is 10 columns (10 characters, 14 bytes)"

# ---- clip_plain: clip from the right ---------------------------------------

# max < 1. The non-ASCII case is the one that proves the guard exists: with the
# guard gone the ASCII fast path errors out to an empty string anyway and the
# assertion would pass for the wrong reason, while "中文字" would come back "…".
assert_eq "" "$(clip_plain 'abcdef' 0)"  "max 0 is empty"
assert_eq "" "$(clip_plain '中文字' 0)"   "max 0 is empty, wide chars included"
assert_eq "" "$(clip_plain '中文字' -1)"  "negative max is empty"

# Exact fit is NOT clipped; one over is.
assert_eq "abcdef" "$(clip_plain 'abcdef' 6)" "exact fit keeps the string whole"
assert_eq "abcdef" "$(clip_plain 'abcdef' 7)" "room to spare keeps the string whole"
assert_eq "abcd…"  "$(clip_plain 'abcdef' 5)" "one column over: clipped with an ellipsis"
assert_eq "ab…"    "$(clip_plain 'abcdef' 3)" "clipped to 3 columns"
assert_eq "…"      "$(clip_plain 'abcdef' 1)" "max 1 is just the ellipsis"

# Exact fit measured in COLUMNS, not characters: 3 characters, 6 columns.
assert_eq "中文字" "$(clip_plain '中文字' 6)" "3 CJK chars fit exactly in 6 columns"
assert_eq "中文…"  "$(clip_plain '中文字' 5)" "one column over: the ellipsis costs 1, not 3"
# 4 columns cannot hold 中文 (4) plus the ellipsis (1), and 文 cannot be halved,
# so it is dropped entirely and the result is deliberately NARROWER than max.
assert_eq "中…"    "$(clip_plain '中文字' 4)" "a wide char that would straddle the budget is dropped"
assert_eq "…"      "$(clip_plain '中文字' 2)" "no wide char fits beside the ellipsis"
assert_eq "…"      "$(clip_plain '中文字' 1)" "max 1 is just the ellipsis"
assert_eq "a…"     "$(clip_plain 'a中b' 3)"  "mixed: 中 would straddle, so it is dropped"

assert_eq "Tiếng-Việt" "$(clip_plain 'Tiếng-Việt' 10)" "10 columns is an exact fit, not 14 bytes"
assert_eq "Tiến…"      "$(clip_plain 'Tiếng-Việt' 5)"  "diacritics clip at one column each"

# The output is emitted with printf '%s…' "$out", so text is data: a name holding
# a % or a backslash escape must come back byte-for-byte, never reinterpreted.
assert_eq '100%…' "$(clip_plain '100%中文' 5)" "a % in the clipped text stays a %"
assert_eq 'a\n…'  "$(clip_plain 'a\nb中' 4)"   "a literal \\n stays two characters"

# ---- shorten_left: clip from the left, keep the tail -----------------------

assert_eq "" "$(shorten_left 'abcdef' 0)" "max 0 is empty"
assert_eq "" "$(shorten_left '中文字' 0)"  "max 0 is empty, wide chars included"
assert_eq "" "$(shorten_left '中文字' -1)" "negative max is empty"

assert_eq "abcdef" "$(shorten_left 'abcdef' 6)" "exact fit keeps the string whole"
assert_eq "abcdef" "$(shorten_left 'abcdef' 7)" "room to spare keeps the string whole"
assert_eq "…cdef"  "$(shorten_left 'abcdef' 5)" "keeps the TAIL and prefixes the ellipsis"
assert_eq "…ef"    "$(shorten_left 'abcdef' 3)" "clipped to 3 columns from the left"
# The cell that was missing while the fast path was dead, and the defect it hid:
# spelled `${s: -$((max - 1))}`, this returned '…abcdef' — a 7-column answer to a
# 1-column budget — because -0 is not negative and bash reads it as offset 0.
assert_eq "…"      "$(shorten_left 'abcdef' 1)" "max 1 is just the ellipsis"

assert_eq "中文字" "$(shorten_left '中文字' 6)" "3 CJK chars fit exactly in 6 columns"
assert_eq "…文字"  "$(shorten_left '中文字' 5)" "one column over: drops the head"
assert_eq "…字"    "$(shorten_left '中文字' 4)" "a wide char that would straddle the budget is dropped"
assert_eq "…"      "$(shorten_left '中文字' 2)" "no wide char fits beside the ellipsis"
assert_eq "…"      "$(shorten_left '中文字' 1)" "max 1 is just the ellipsis"

assert_eq "Tiếng-Việt" "$(shorten_left 'Tiếng-Việt' 10)" "10 columns is an exact fit, not 14 bytes"
assert_eq "…Việt"      "$(shorten_left 'Tiếng-Việt' 5)"  "keeps the tail, one column per diacritic"

# The real shape of the input: a repo path whose tail names the project.
assert_eq "…ジェクト" "$(shorten_left 'code/プロジェクト' 10)" \
    "repo path keeps the project end; 4 Kana + … is 9 of the 10 columns"

# ---- the invariant, asserted directly --------------------------------------
#
# For any input and any max >= 1 the clipped result must measure at most max
# display columns. This is what an off-by-one in the budget looks like: the
# string still reads fine, it is simply one column too wide, and the row wraps.

for s in 'abcdef' '中文字' 'a中b' 'Tiếng-Việt' 'プロジェクト' '…' '100%中文'; do
    for m in 1 2 3 4 5 6 7 8 12; do
        assert_ok "clip_plain([$s], $m) fits in $m columns" fits clip_plain "$s" "$m"
    done
done

# Same battery for shorten_left, from max 1 like clip_plain's above. It started
# at 2 while the ASCII fast path was dead code, which is what let the `${s: -0}`
# defect sit in it unseen.
for s in 'abcdef' '中文字' 'a中b' 'Tiếng-Việt' 'プロジェクト' '…' '100%中文'; do
    for m in 1 2 3 4 5 6 7 8 12; do
        assert_ok "shorten_left([$s], $m) fits in $m columns" fits shorten_left "$s" "$m"
    done
done

test_summary
