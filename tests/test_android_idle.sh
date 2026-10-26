#!/bin/bash
# The "android-idle-images" rule kind (cdm's avd_last_started, avd_image_users and
# register_idle_images) — offers, one row each, the emulator system images that
# only IDLE AVDs boot from. See docs/DESIGN.md#android-idle-images.
#
# The sibling kind, android-images, never offers an image an AVD boots from.
# This one does, on purpose, and that is why its assertions are mostly refusals:
#
#   * an image some AVD started within idleDays is never offered, even when
#     another AVD on the same image has been idle for a year;
#   * an image no AVD boots is not this row's business (android-images has it);
#   * the age is when the emulator last WROTE into the AVD — config.ini does not
#     count, because Android Studio rewrites it without booting anything;
#   * a row names the AVDs it would leave unbootable, once each, even though
#     avd_configs finds a typical AVD twice (as <name>.avd and via <name>.ini);
#   * no usable idleDays means no idea what idle is: nothing is offered.

. "$(dirname "$0")/lib.sh"

unset ANDROID_AVD_HOME ANDROID_USER_HOME

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0; PARSED_OK=0; }

# age <days> <path...> — set each path's mtime that many days back.
age() {
    local d="$1" t; shift
    t=$(date -v-"${d}"d +%Y%m%d%H%M.%S)
    touch -t "$t" "$@"
}

SDK="$HOME/Library/Android/sdk/system-images"
TV="$SDK/android-34/android-tv/arm64-v8a"
PHONE="$SDK/android-35/google_apis/arm64-v8a"
SPARE="$SDK/android-33/google_apis/arm64-v8a"
for d in "$TV" "$PHONE" "$SPARE"; do mkdir -p "$d"; echo img > "$d/system.img"; done

AVD="$HOME/.android/avd"
# mkavd <name> <image ref> <days since it ran> — an AVD as Android Studio leaves
# it: config.ini, the <name>.ini that points at it, and the files the emulator
# writes when it runs. config.ini is touched today, as Studio's edits do.
mkavd() {
    mkdir -p "$AVD/$1.avd"
    printf 'avd.ini.encoding=UTF-8\nimage.sysdir.1=%s/\n' "$2" > "$AVD/$1.avd/config.ini"
    printf 'path=%s\n' "$AVD/$1.avd" > "$AVD/$1.ini"
    echo x > "$AVD/$1.avd/hardware-qemu.ini"; echo x > "$AVD/$1.avd/userdata-qemu.img.qcow2"
    age "$3" "$AVD/$1.avd/hardware-qemu.ini" "$AVD/$1.avd/userdata-qemu.img.qcow2"
}
mkavd atv34 "system-images/android-34/android-tv/arm64-v8a" 81
mkavd pixel "system-images/android-35/google_apis/arm64-v8a" 3

IMAGES="~/Library/Android/sdk/system-images/*/*/*"

# ---- avd_last_started -------------------------------------------------------

t_now=$(date +%s)
t_last=$(avd_last_started "$AVD/atv34.avd")
assert_ok "atv34 last ran about 81 days ago, not today (config.ini left out)" \
    test $(( (t_now - t_last) / 86400 )) -ge 80
mkdir -p "$AVD/fresh.avd"; printf 'image.sysdir.1=x/\n' > "$AVD/fresh.avd/config.ini"
age 5 "$AVD/fresh.avd/config.ini"
assert_eq "$(stat -f %m "$AVD/fresh.avd/config.ini")" "$(avd_last_started "$AVD/fresh.avd")" \
    "an AVD that never ran is as old as its config.ini"
rm -rf "$AVD/fresh.avd"
assert_eq "0" "$(avd_last_started "$HOME/no-such.avd")" "no AVD folder: 0"

# ---- avd_image_users --------------------------------------------------------

assert_eq "system-images/android-34/android-tv/arm64-v8a|atv34" \
    "$(avd_image_users | tr '\037' '|' | cut -d '|' -f 1,2 | LC_ALL=C sort -u | grep atv34)" \
    "a user line: the SDK-relative ref and the AVD's name"

# ---- register_idle_images ---------------------------------------------------

reset_cats
register_idle_images "i" "Idle AVD image" rm 0 "D." "$IMAGES" 60
assert_eq 1 "$N" "one row: the TV image only atv34 boots"
assert_eq "Idle AVD image: android-34/android-tv/arm64-v8a" "${CAT_NAME[0]:-}" "the row names the image"
assert_eq "$TV" "${CAT_PATHS[0]:-}" "the row deletes the image and nothing else"
t_since=$(date -r "$t_last" +%Y-%m-%d)
assert_eq "atv34 · idle since $t_since" "${CAT_SUMMARY[0]:-}" "the summary names the AVD once, with its last start"
assert_eq "Booted only by atv34, last started $t_since. D. Reinstall: sdkmanager \"system-images;android-34;android-tv;arm64-v8a\"" \
    "${CAT_DESC[0]:-}" "the description names the AVD and the package to reinstall"
assert_eq "rm|0" "${CAT_METHOD[0]:-}|${CAT_DEFAULT[0]:-}" "the rule's method and default are kept"

# A second, recently used AVD on the same image keeps it.
mkavd tv2 "system-images/android-34/android-tv/arm64-v8a" 1
reset_cats
register_idle_images "i" "Idle AVD image" rm 0 "D." "$IMAGES" 60
assert_eq 0 "$N" "one recent AVD on the image keeps it, however idle the other"
rm -rf "$AVD/tv2.avd" "$AVD/tv2.ini"

# Two idle AVDs on one image: both named.
mkavd tv3 "system-images/android-34/android-tv/arm64-v8a" 200
reset_cats
register_idle_images "i" "Idle AVD image" rm 0 "D." "$IMAGES" 60
assert_eq "atv34, tv3" "${CAT_SUMMARY[0]%% ·*}" "every idle AVD on the image is named"
rm -rf "$AVD/tv3.avd" "$AVD/tv3.ini"

# The threshold is the rule's: at 90 days atv34 is not idle yet.
reset_cats
register_idle_images "i" "Idle AVD image" rm 0 "D." "$IMAGES" 90
assert_eq 0 "$N" "idleDays 90: an AVD last run 81 days ago is not idle"

# No usable idleDays: nothing.
reset_cats; register_idle_images "i" "Idle AVD image" rm 0 "D." "$IMAGES" ""
assert_eq 0 "$N" "no idleDays offers nothing"
reset_cats; register_idle_images "i" "Idle AVD image" rm 0 "D." "$IMAGES" "6O"
assert_eq 0 "$N" "a non-numeric idleDays offers nothing"

# No AVDs at all: the unused-images row's case, not this one.
mv "$AVD" "$HOME/avd.off"
reset_cats
register_idle_images "i" "Idle AVD image" rm 0 "D." "$IMAGES" 60
assert_eq 0 "$N" "no AVD boots anything: nothing is idle"
mv "$HOME/avd.off" "$AVD"

# ---- the shipped rules --------------------------------------------------------

reset_cats
parse_pattern_stream "$CDM_ROOT/rules/dev-caches.json"
t_idle=""; t_unused=""
for i in $(cat_indices); do
    case "${CAT_NAME[$i]}" in
        "Idle AVD image: "*) t_idle="${t_idle}${CAT_PATHS[$i]}|${CAT_DEFAULT[$i]};" ;;
        "Unused Android system images") t_unused="${CAT_PATHS[$i]}" ;;
    esac
done
assert_eq "$TV|0;" "$t_idle" "shipped dev-caches.json: the idle TV image, unchecked"
assert_eq "$SPARE" "$t_unused" "shipped dev-caches.json: the unused image stays in its own row"

test_summary
