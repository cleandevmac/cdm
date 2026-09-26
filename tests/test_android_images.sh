#!/bin/bash
# The "android-images" rule kind (cdm's avd_image_refs + register_paths' skip
# list) — offers Android emulator system images that NO AVD boots from.
#
# A system image is several GB, and the leak is ordinary: create an AVD, delete
# it later, and its image stays in the SDK forever. But the image an AVD still
# uses is not junk — delete it and that emulator no longer boots. The rule
# supplies the candidate globs; the script drops every candidate some AVD's
# config.ini names in image.sysdir.N. The load-bearing property is the second
# half, so most assertions below are about what is NOT offered.
# See docs/DESIGN.md#android-images.

. "$(dirname "$0")/lib.sh"

# The developer's own AVD locations must not leak in; the sandbox decides.
unset ANDROID_AVD_HOME ANDROID_USER_HOME

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0; PARSED_OK=0; }

SDK="$HOME/Library/Android/sdk/system-images"
USED="$SDK/android-34/android-tv/arm64-v8a"
ELSEWHERE="$SDK/android-33/google_apis/arm64-v8a"
UNUSED="$SDK/android-35/google_apis/arm64-v8a"
for d in "$USED" "$ELSEWHERE" "$UNUSED"; do mkdir -p "$d"; echo img > "$d/system.img"; done

AVD="$HOME/.android/avd"
mkdir -p "$AVD/tv.avd"
# Exactly how Android Studio writes it: SDK-relative, WITH a trailing slash.
printf 'avd.ini.encoding=UTF-8\nimage.sysdir.1=system-images/android-34/android-tv/arm64-v8a/\n' \
    > "$AVD/tv.avd/config.ini"
printf 'path=%s\ntarget=android-34\n' "$AVD/tv.avd" > "$AVD/tv.ini"

# An AVD stored outside the AVD home — reachable only through its <name>.ini's
# path= line, never through the *.avd glob.
FAR="$HOME/elsewhere/phone.avd"
mkdir -p "$FAR"
printf 'image.sysdir.1 = system-images/android-33/google_apis/arm64-v8a/\r\n' > "$FAR/config.ini"
printf 'path=%s\n' "$FAR" > "$AVD/phone.ini"

# ---- avd_image_refs ---------------------------------------------------------

refs=$(avd_image_refs | LC_ALL=C sort -u)
assert_eq "system-images/android-33/google_apis/arm64-v8a
system-images/android-34/android-tv/arm64-v8a" "$refs" \
    "refs: both AVDs found, trailing slash / spaces / CR stripped"

# ---- ends_with_any ----------------------------------------------------------

assert_ok   "suffix on a / boundary matches" ends_with_any "$USED" "system-images/android-34/android-tv/arm64-v8a"
assert_fail "suffix mid-component does not"  ends_with_any "$SDK/android-34/android-tv/xarm64-v8a" "arm64-v8a"
assert_ok   "absolute ref matches itself"    ends_with_any "$USED" "$USED"
assert_fail "empty list matches nothing"     ends_with_any "$USED" ""

# ---- the rule round-trip ----------------------------------------------------

RULES=$(mktemp -d "$HOME/rules.XXXXXX")
cat > "$RULES/android.json" <<'JSON'
{ "categories": [ {
    "kind": "android-images", "icon": "x", "name": "Unused Android system images",
    "method": "rm", "default": false, "desc": "d",
    "images": [ "~/Library/Android/sdk/system-images/*/*/*" ]
} ] }
JSON

reset_cats
parse_pattern_stream "$RULES/android.json"
assert_eq 1 "$N" "android-images category registered"
assert_eq "$UNUSED" "${CAT_PATHS[0]:-}" "only the image no AVD uses is offered"

# No AVDs at all: every image is unused.
mv "$AVD" "$HOME/avd.off"
reset_cats
parse_pattern_stream "$RULES/android.json"
assert_eq 3 "$(printf '%s\n' "${CAT_PATHS[0]:-}" | grep -c .)" "no AVDs: all three images offered"
mv "$HOME/avd.off" "$AVD"

# ANDROID_AVD_HOME is honoured on top of ~/.android/avd.
mkdir -p "$HOME/custom-avd/x.avd"
printf 'image.sysdir.1=system-images/android-35/google_apis/arm64-v8a/\n' > "$HOME/custom-avd/x.avd/config.ini"
reset_cats
ANDROID_AVD_HOME="$HOME/custom-avd" parse_pattern_stream "$RULES/android.json"
assert_eq 0 "$N" "ANDROID_AVD_HOME's AVD keeps the last image too"
rm -rf "$HOME/custom-avd"

# The candidates travel in "images", never "paths": an older cdm that does not
# know this kind falls through to plain register_paths, and must find nothing
# rather than every image including the ones in use.
reset_cats
sed 's/"kind": "android-images"/"kind": "some-future-kind"/' "$RULES/android.json" > "$RULES/old.json"
parse_pattern_stream "$RULES/old.json"
assert_eq 0 "$N" "unknown kind with only 'images' registers nothing"

# ---- the shipped rules ------------------------------------------------------

reset_cats
parse_pattern_stream "$CDM_ROOT/rules/dev-caches.json"
got=""
for i in $(cat_indices); do
    [ "${CAT_NAME[$i]}" = "Unused Android system images" ] && got="${CAT_PATHS[$i]}"
done
assert_eq "$UNUSED" "$got" "shipped dev-caches.json: only the unused image"

test_summary
