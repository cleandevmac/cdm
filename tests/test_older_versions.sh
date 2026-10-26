#!/bin/bash
# The "older-versions" rule kind (cdm's newest_version + register_older) — offers
# every version in a family of siblings except the newest, e.g. all the Android
# build-tools and SDK platforms but the latest of each. See
# docs/DESIGN.md#older-versions.
#
# What the assertions below are shaped around:
#
#   * "newest" is a VERSION comparison, not a string one. As strings, 9 sorts
#     above 10 and android-36 above android-36.1 never mind 37.0; Android 16
#     introduced minor API levels (android-36.1), so the comparison has to treat
#     a missing field as 0 rather than as "shorter is smaller". Every ordering
#     below is one a plain sort gets wrong.
#   * a release outranks its own pre-release: keep 36.0.0, offer 36.0.0-rc1.
#   * the newest of each family is never offered, and a family of one offers
#     nothing — so the load-bearing assertions are about what is NOT in the row.
#   * the candidates travel in "candidates", never "paths": a cdm too old to know
#     the kind must find nothing rather than every version, newest included.

. "$(dirname "$0")/lib.sh"

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0; PARSED_OK=0; }

# newest <name...> — newest_version over /x/<name> paths, answered by name.
newest() {
    local list="" n
    for n in "$@"; do list="${list:+$list$NL}/x/$n"; done
    n=$(newest_version "$list"); printf '%s' "${n##*/}"
}

# ---- newest_version ---------------------------------------------------------

assert_eq "37.0.0"       "$(newest 34.0.0 37.0.0 36.1.0 35.0.0 36.0.0)" "build-tools: the highest version"
assert_eq "10.0.0"       "$(newest 9.0.0 10.0.0)" "10 is newer than 9 (numbers, not strings)"
assert_eq "android-37.0" "$(newest android-35 android-37.0 android-36.1)" "platforms: 37.0 above 36.1 above 35"
assert_eq "android-36.1" "$(newest android-36.1 android-36)" "android-36.1 is newer than android-36"
assert_eq "36.0.0"       "$(newest 36.0.0-rc1 36.0.0)" "a release outranks its own pre-release"
assert_eq "36.0.1-rc1"   "$(newest 36.0.0 36.0.1-rc1)" "a pre-release of a later version still wins"
assert_eq "android-34"   "$(newest android-UpsideDownCake android-34)" "a codename with no number is oldest"
assert_eq "26.1.10909125" "$(newest 25.2.9519653 26.1.10909125)" "NDK versions"
assert_eq "07.1"         "$(newest 6.9 07.1)" "a leading zero does not make a field smaller"
assert_eq "single"       "$(newest single)" "a list of one returns it"

# ---- register_older ---------------------------------------------------------

SDK="$HOME/Library/Android/sdk"
for v in 34.0.0 35.0.0 36.0.0 36.1.0 37.0.0; do mkdir -p "$SDK/build-tools/$v"; echo x > "$SDK/build-tools/$v/aapt"; done
for v in android-35 android-36.1 android-37.0; do mkdir -p "$SDK/platforms/$v"; echo x > "$SDK/platforms/$v/android.jar"; done
mkdir -p "$SDK/ndk/25.2.9519653"; echo x > "$SDK/ndk/25.2.9519653/source.properties"
mkdir -p "$SDK/build-tools/38.0.0"    # empty: not installed, so not the newest either

reset_cats
register_older "i" "Older" rm 0 "d" "~/Library/Android/sdk/build-tools/*
~/Library/Android/sdk/platforms/*
~/Library/Android/sdk/ndk/*"
assert_eq 1 "$N" "one category for every family together"
assert_eq "$SDK/build-tools/34.0.0
$SDK/build-tools/35.0.0
$SDK/build-tools/36.0.0
$SDK/build-tools/36.1.0
$SDK/platforms/android-35
$SDK/platforms/android-36.1" "${CAT_PATHS[0]:-}" \
    "all but the newest of each family; a family of one (ndk) and an empty dir offer nothing"
assert_eq "rm|0" "${CAT_METHOD[0]:-}|${CAT_DEFAULT[0]:-}" "the rule's method and default are kept"

# Every family down to one version: nothing to offer, no row.
rm -rf "$SDK/build-tools/34.0.0" "$SDK/build-tools/35.0.0" "$SDK/build-tools/36.0.0" \
       "$SDK/build-tools/36.1.0" "$SDK/platforms/android-35" "$SDK/platforms/android-36.1"
reset_cats
register_older "i" "Older" rm 0 "d" "~/Library/Android/sdk/build-tools/*
~/Library/Android/sdk/platforms/*"
assert_eq 0 "$N" "only the newest left in each family: no row"

# A rule's procs ride along, as register_paths' do.
mkdir -p "$SDK/build-tools/36.0.0"; echo x > "$SDK/build-tools/36.0.0/aapt"
reset_cats
register_older "i" "Older" rm 0 "d" "~/Library/Android/sdk/build-tools/*" "studio"
assert_eq "studio" "${CAT_PROCS[0]:-}" "the rule's procs reach the row"
rm -rf "$SDK/build-tools/36.0.0"

# Two patterns naming the same versions offer each once.
mkdir -p "$SDK/build-tools/36.0.0"; echo x > "$SDK/build-tools/36.0.0/aapt"
reset_cats
register_older "i" "Older" rm 0 "d" "~/Library/Android/sdk/build-tools/*
~/Library/Android/sdk/build-tools/3*"
assert_eq "$SDK/build-tools/36.0.0" "${CAT_PATHS[0]:-}" "a version two patterns reach is offered once"

# ---- the rule round-trip -----------------------------------------------------

RULES=$(mktemp -d "$HOME/rules.XXXXXX")
cat > "$RULES/older.json" <<'JSON'
{ "categories": [ {
    "kind": "older-versions", "icon": "x", "name": "Older Android build-tools & platforms",
    "method": "rm", "default": false, "desc": "d",
    "candidates": [ "~/Library/Android/sdk/build-tools/*" ]
} ] }
JSON
reset_cats
parse_pattern_stream "$RULES/older.json"
assert_eq "$SDK/build-tools/36.0.0" "${CAT_PATHS[0]:-}" "older-versions rule: the older version only"

# An older cdm does not know the kind and falls back to "paths" — which is empty.
sed 's/"kind": "older-versions"/"kind": "some-future-kind"/' "$RULES/older.json" > "$RULES/old.json"
reset_cats
parse_pattern_stream "$RULES/old.json"
assert_eq 0 "$N" "unknown kind with only 'candidates' registers nothing"

test_summary
