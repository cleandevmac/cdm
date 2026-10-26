#!/bin/bash
# The shipped rules for installed SDK pieces that download again — PlatformIO's
# platforms and toolchains, and the Android NDK, CMake and SDK sources — run
# against a fake home laid out the way those tools lay theirs out. These rows are
# plain data (rules/dev-caches.json), so what is under test is the data: which
# folders each row reaches, and above all which it never does.
#
#   * PlatformIO: penv is PlatformIO's own Python, i.e. the `pio` command, and
#     appstate.json / idf-env.json are its state. None may be offered. dist/
#     holds only the archives ESP32 tools were unpacked from, so it joins the
#     pre-selected download cache; packages/, platforms/ and tools/ are installed
#     software and arrive unchecked.
#   * Android: cmdline-tools holds sdkmanager (needed to reinstall everything
#     else), platform-tools holds adb, and emulator runs every AVD. None may be
#     offered.
#   * every new row that removes installed software arrives unchecked.

. "$(dirname "$0")/lib.sh"

unset ANDROID_AVD_HOME ANDROID_USER_HOME

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0; PARSED_OK=0; }
put() { mkdir -p "$(dirname "$1")"; echo x > "$1"; }

PIO="$HOME/.platformio"
put "$PIO/appstate.json"; put "$PIO/idf-env.json"
put "$PIO/penv/bin/pio"
put "$PIO/.cache/downloads/x.tar.gz"
put "$PIO/dist/xtensa-esp-elf-14.2.0.tar.xz"
put "$PIO/packages/toolchain-xtensa-esp-elf/bin/gcc"
put "$PIO/packages/framework-arduinoespressif32-libs/lib.a"
put "$PIO/platforms/espressif32/platform.json"
put "$PIO/tools/toolchain-xtensa-esp-elf/package.json"

SDK="$HOME/Library/Android/sdk"
put "$SDK/ndk/25.2.9519653/source.properties"
put "$SDK/ndk-bundle/source.properties"
put "$SDK/cmake/3.22.1/bin/cmake"
put "$SDK/sources/android-36.1/android/app/Activity.java"
put "$SDK/cmdline-tools/latest/bin/sdkmanager"
put "$SDK/platform-tools/adb"
put "$SDK/emulator/emulator"

reset_cats
parse_pattern_stream "$CDM_ROOT/rules/dev-caches.json"
# row <name> — "<default>|<paths, one per line>" of the shipped row of that name.
row() {
    local i
    for i in $(cat_indices); do
        [ "${CAT_NAME[$i]}" = "$1" ] && { printf '%s|%s' "${CAT_DEFAULT[$i]}" "${CAT_PATHS[$i]}"; return; }
    done
}

assert_eq "1|$PIO/.cache
$PIO/dist" "$(row "PlatformIO download cache")" "PlatformIO download cache: .cache and dist, pre-selected"
assert_eq "0|$PIO/packages/framework-arduinoespressif32-libs
$PIO/packages/toolchain-xtensa-esp-elf
$PIO/platforms/espressif32
$PIO/tools/toolchain-xtensa-esp-elf" "$(row "PlatformIO platforms & toolchains")" \
    "PlatformIO platforms & toolchains: each installed package, platform and tool, unchecked"

assert_eq "0|$SDK/ndk/25.2.9519653
$SDK/ndk-bundle
$SDK/cmake/3.22.1
$SDK/sources/android-36.1" "$(row "Android NDK, CMake & SDK sources")" \
    "Android NDK, CMake & SDK sources: those, unchecked"

# Nothing any row offers may be PlatformIO's own runtime or state, or the SDK's
# own tools.
t_never=""
for i in $(cat_indices); do
    while IFS= read -r p; do
        case "$p" in
            "$PIO"/penv*|"$PIO"/appstate.json|"$PIO"/idf-env.json|"$PIO"|\
            "$SDK"/cmdline-tools*|"$SDK"/platform-tools*|"$SDK"/emulator*|"$SDK")
                t_never="$t_never ${p#$HOME/}" ;;
        esac
    done <<EOF
${CAT_PATHS[$i]}
EOF
done
assert_eq "" "$t_never" "no row offers penv, PlatformIO's state, sdkmanager, adb or the emulator"

# Every kind-driven row in the shipped file that removes installed software
# arrives unchecked. Read off the JSON itself, so a new row is held to it too.
t_checked=$(osascript -l JavaScript -e '
    ObjC.import("Foundation");
    var s = $.NSString.stringWithContentsOfFileEncodingError($("'"$CDM_ROOT"'/rules/dev-caches.json"), $.NSUTF8StringEncoding, null).js;
    JSON.parse(s).categories.filter(function (c) {
        return c.kind && c.kind !== "paths" && c["default"];
    }).map(function (c) { return c.name; }).join(",");' 2>/dev/null)
assert_eq "" "$t_checked" "no kind-driven row in dev-caches.json arrives pre-selected"

test_summary
