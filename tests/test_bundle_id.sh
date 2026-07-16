#!/bin/bash
# cdm's looks_like_bundle_id — the shape filter standing in front of the orphan
# scan. It decides which directory names are even CONSIDERED for a bundle-id
# match, and so which are eligible to be OFFERED FOR DELETION. That makes its
# accepted set a behavioural contract, not a formatting detail, and the reason
# every assertion below pins the locale it runs under.
#
# The set is the one Apple documents — "only alphanumeric characters (A–Z, a–z,
# 0–9), hyphens (-), and periods (.)" — plus the underscore, which cdm allows
# deliberately (see docs/DESIGN.md#bundle-id-shape). All ASCII.
#
# The bug this file exists to keep out: the guard was `*[!A-Za-z0-9._-]*`, a
# bracket RANGE, resolved by LC_COLLATE — which cdm deliberately does not pin.
# So the orphan list depended on the user's LANG. Two directions are pinned
# below, because the second is the trap in the FIX rather than in the bug:
#
#   * a RANGE is too NARROW a guard — under en_US.UTF-8 accented letters collate
#     inside [A-Za-z], so com.füü.bar was a deletion candidate there and not
#     under C;
#   * a bare CLASS is too WIDE — cdm's pin forces a UTF-8 ctype, under which
#     [[:alnum:]] means "any alphanumeric in Unicode", so `*[![:alnum:]._-]*`
#     would newly accept com.日本.app (rejected under every collation today) and
#     offer a folder named 私の.大切な.データ for deletion. Consistent, and
#     consistently wrong.
#
# Only the composition — is_ascii THEN [[:alnum:]._-] — is both. Note that with
# is_ascii in front, swapping the class back to the old range is an EQUIVALENT
# mutant: only ASCII reaches the second case, and over ASCII the two accept the
# same characters. is_ascii is the guard doing the locale-proofing, which is why
# tests/mutate.sh asserts on removing it rather than on the class's spelling.
#
# Not a safety test. Nothing here is cdm's trust boundary — is_safe_target is,
# and it gates every deletion regardless of what this function says. The
# metacharacter and traversal cases below are pinned because they are cheap and
# because a widened shape filter is how a name reaches that boundary at all.

. "$(dirname "$0")/lib.sh"

# ---- premises ---------------------------------------------------------------
#
# These touch no cdm code. They assert only that the hostile locales really are
# hostile — because bash falls back to C collation SILENTLY on an unknown locale
# (no diagnostic, exit 0), so if en_US.UTF-8 ever stopped resolving on a machine,
# every assertion below would pass vacuously under C and prove nothing. If one of
# these fails, this file has lost its teeth: find out why rather than deleting it.

# The bug's mechanism: does an accented letter collate inside [A-Za-z]?
range_has_e() { ( LC_ALL="$1"; case 'é' in [A-Za-z]) printf 'yes' ;; *) printf 'no' ;; esac ); }
assert_eq yes "$(range_has_e en_US.UTF-8)" "premise: under en_US collation [A-Za-z] contains 'é'"
assert_eq no  "$(range_has_e C)"           "premise: under C collation it does not"

# The fix's trap: is a bare [[:alnum:]] wider than ASCII under a UTF-8 ctype?
# This is why is_ascii is composed in rather than the class used alone.
class_has() { ( LC_ALL="$1"; case "$2" in [[:alnum:]]) printf 'yes' ;; *) printf 'no' ;; esac ); }
assert_eq yes "$(class_has en_US.UTF-8 'é')" "premise: [[:alnum:]] accepts 'é' under a UTF-8 ctype"
assert_eq yes "$(class_has en_US.UTF-8 '日')" "premise: [[:alnum:]] accepts '日' under a UTF-8 ctype"
assert_eq no  "$(class_has C 'é')"           "premise: and does not under a C ctype"

# ---- the locales ------------------------------------------------------------
#
# Three real arrivals, and the answer must not vary across them: en_US.UTF-8 is
# what a Terminal exports, C is a bare ssh/launchd, C.UTF-8 is the pair between
# them (UTF-8 ctype, C collation) and is what this repo's own developer shell
# exports — which is exactly how the is_ascii bug reached CI unseen.
LOCALES='en_US.UTF-8 C C.UTF-8'

# ---- the shape rule: reverse-DNS, two dots ----------------------------------

for loc in $LOCALES; do
    assert_ok   "com.foo.bar is bundle-id shaped under $loc"  in_locale "$loc" looks_like_bundle_id 'com.foo.bar'
    assert_ok   "four segments are fine under $loc"           in_locale "$loc" looks_like_bundle_id 'com.foo.app.ShipIt'
    assert_fail "one dot is not enough under $loc"            in_locale "$loc" looks_like_bundle_id 'com.foo'
    assert_fail "no dots at all under $loc"                   in_locale "$loc" looks_like_bundle_id 'Preferences'
    assert_fail "empty string under $loc"                     in_locale "$loc" looks_like_bundle_id ''
done

# ---- the accepted set: ASCII alnum plus . _ - -------------------------------

for loc in $LOCALES; do
    assert_ok "digits are accepted under $loc"         in_locale "$loc" looks_like_bundle_id 'com.foo.app2'
    assert_ok "hyphens are accepted under $loc"        in_locale "$loc" looks_like_bundle_id 'com.foo-bar.app'
    assert_ok "underscores are accepted under $loc"    in_locale "$loc" looks_like_bundle_id 'com.foo_bar.app_1'
    assert_ok "uppercase is accepted under $loc"       in_locale "$loc" looks_like_bundle_id 'COM.Foo.App'
    assert_ok "a leading dot is accepted under $loc"   in_locale "$loc" looks_like_bundle_id '.com.foo.bar'
done

# ---- non-ASCII is refused, under EVERY locale — the bug ---------------------
#
# These are the cells that differed. Under the old range guard every one of them
# was ACCEPTED under en_US.UTF-8 and REJECTED under C: the same machine offering
# a different set of files for deletion depending on LANG. A real bundle id
# cannot contain any of these characters, so refusing them everywhere is both
# consistent and correct.

for loc in $LOCALES; do
    assert_fail "an umlaut is refused under $loc"       in_locale "$loc" looks_like_bundle_id 'com.füü.bar'
    assert_fail "an acute accent is refused under $loc" in_locale "$loc" looks_like_bundle_id 'com.foo.é-app'
    assert_fail "an eszett is refused under $loc"       in_locale "$loc" looks_like_bundle_id 'com.ß.app'
    assert_fail "a tilde-n is refused under $loc"       in_locale "$loc" looks_like_bundle_id 'com.ñ.x'
    assert_fail "Vietnamese is refused under $loc"      in_locale "$loc" looks_like_bundle_id 'com.Tiếng.Việt'
done

# ---- CJK is refused too — the trap in the FIX, not in the bug ---------------
#
# Separated from the block above because these fail for a different reason and
# guard a different mistake. The old RANGE already rejected these under every
# locale; a bare [[:alnum:]._-] would ACCEPT them under every locale cdm can run
# in, since the pin forces a UTF-8 ctype. So these assertions are what stands
# between the fix and a wider deletion-candidate set than the bug ever had. The
# last is the one that matters: 私の.大切な.データ is "my.precious.data", two dots,
# every character alnum — a folder, not a bundle id, and not one to offer up.

for loc in $LOCALES; do
    assert_fail "CJK is refused under $loc"          in_locale "$loc" looks_like_bundle_id 'com.日本.app'
    assert_fail "Kana is refused under $loc"         in_locale "$loc" looks_like_bundle_id 'com.プロジェクト.app'
    assert_fail "Hangul is refused under $loc"       in_locale "$loc" looks_like_bundle_id 'com.한국.app'
    assert_fail "Cyrillic is refused under $loc"     in_locale "$loc" looks_like_bundle_id 'com.Проект.app'
    assert_fail "私の.大切な.データ is not a bundle id under $loc" in_locale "$loc" looks_like_bundle_id '私の.大切な.データ'
done

# ---- and the characters that must never be in a candidate name --------------
#
# Byte-identical under both collations before and after this change, so none of
# these is the fix — they are pinned so that a future widening of the set has to
# walk past an assertion saying so.

for loc in $LOCALES; do
    assert_fail "a slash is refused under $loc"          in_locale "$loc" looks_like_bundle_id 'com.foo/etc.bar'
    assert_fail "traversal is refused under $loc"        in_locale "$loc" looks_like_bundle_id '../../x.y.z'
    assert_fail "a space is refused under $loc"          in_locale "$loc" looks_like_bundle_id 'com.foo bar.app'
    assert_fail "a glob star is refused under $loc"      in_locale "$loc" looks_like_bundle_id 'com.a.b*c'
    assert_fail "a newline is refused under $loc"        in_locale "$loc" looks_like_bundle_id 'com.a.b
c'
    assert_fail "a backslash is refused under $loc"      in_locale "$loc" looks_like_bundle_id 'com.a.b\c'
    assert_fail "command substitution is refused under $loc" in_locale "$loc" looks_like_bundle_id 'com.$(id).x'
done

test_summary
