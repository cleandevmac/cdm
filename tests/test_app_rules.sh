#!/bin/bash
# The shipped rules for app downloads that come back on their own — Claude
# desktop's older Claude Code builds, Zed's language servers, Chrome's speech and
# text-recognition models, macOS aerial videos, VS Code's agent SDK, EasyEDA's
# Chromium caches, Gemini's installed update and wrangler's logs — run against a
# fake home laid out the way those apps lay theirs out. These rows are plain data
# (rules/app-caches.json, rules/dev-caches.json), so what is under test is the
# data: which folders each row reaches, and above all which it never does.
#
#   * Claude desktop runs new sessions from the newest build in claude-code/, so
#     that one is never offered, and claude-code-vm/ with a single build offers
#     nothing. The row arrives unchecked, like every row that removes software.
#   * Zed keeps settings in ~/.config/zed and its workspace db, extensions and
#     agent threads beside the downloads; none of those may be offered.
#   * Chrome's profile folders and the aerial list & thumbnails are user state or
#     cheap to keep; only the model and video folders are offered.
#   * VS Code's agent-host/local-endpoint and agentSessionData hold sessions, and
#     EasyEDA's Local Storage / IndexedDB hold site data: never offered.
#   * wrangler keeps its login in config/default.toml beside the logs.

. "$(dirname "$0")/lib.sh"

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0; PARSED_OK=0; }
put() { mkdir -p "$(dirname "$1")"; echo x > "$1"; }

AS="$HOME/Library/Application Support"

CL="$AS/Claude"
put "$CL/claude-code/2.1.304/6bbba6adc37f/claude.app/Contents/MacOS/claude"
put "$CL/claude-code/2.1.308/a93ded4b1b47/claude.app/Contents/MacOS/claude"
put "$CL/claude-code-vm/2.1.308/claude"
put "$CL/claude-code-vm/.sdk-version"

ZED="$AS/Zed"
put "$ZED/languages/eslint/server.js"
put "$ZED/node/node-v24/bin/node"
put "$ZED/prettier/node_modules/prettier/index.js"
put "$ZED/hang_traces/trace.json"
put "$ZED/db/0-stable/db.sqlite"
put "$ZED/extensions/installed/html/extension.toml"
put "$ZED/threads/threads.db"
put "$HOME/.config/zed/settings.json"
put "$HOME/Library/Caches/Zed/tmp.bin"
put "$HOME/Library/Logs/Zed/Zed.log"

GC="$AS/Google/Chrome"
put "$GC/OptGuideOnDeviceModel/weights.bin"
put "$GC/SODA/1.0/SODAFiles/soda.bin"
put "$GC/SODALanguagePacks/en-US/1.5075.0/model.bin"
put "$GC/screen_ai/153.4/gocr/model.bin"
put "$GC/Default/Preferences"

AER="$AS/com.apple.wallpaper/aerials"
put "$AER/videos/4C108785-A7BA-422E-9C79-B0129F1D5550.mov"
put "$AER/manifest/entries.json"
put "$AER/thumbnails/4C108785.png"
put "$AER/manifest.tar"
put "$AS/com.apple.wallpaper/Store/Index.plist"

put "$AS/Code/agent-host/sdk-cache/claude/0.3.220/darwin-arm64/.complete"
put "$AS/Code/agent-host/local-endpoint/metadata.json"
put "$AS/Code/agentSessionData/00002098-3f0c-4ecc-89ae-04f36e14de01/session.db"

EDA="$HOME/.config/EasyEDA-Pro/cache.arm64.3"
put "$EDA/Cache/Cache_Data/data_0"
put "$EDA/Code Cache/js/index"
put "$EDA/GPUCache/data_0"
put "$EDA/Service Worker/CacheStorage/745a3b0f/index.txt"
put "$EDA/Service Worker/ScriptCache/index"
put "$EDA/Local Storage/leveldb/000003.log"
put "$EDA/IndexedDB/https_pro.easyeda.com_0.indexeddb.leveldb/LOG"

put "$HOME/Library/Caches/com.google.GeminiMacOS/Updates/1.131.4.1198/update.dmg"
put "$HOME/Library/Caches/com.google.GeminiMacOS/Cache.db"

put "$HOME/.wrangler/logs/wrangler-2026-09-28_02-32-42_704.log"
put "$HOME/.wrangler/config/default.toml"
put "$HOME/Library/Preferences/.wrangler/logs/wrangler-2026-10-01_00-00-00_000.log"

reset_cats
parse_pattern_stream "$CDM_ROOT/rules/app-caches.json"
parse_pattern_stream "$CDM_ROOT/rules/dev-caches.json"
# row <name> — "<default>|<paths, one per line>" of the shipped row of that name.
row() {
    local i
    for i in $(cat_indices); do
        [ "${CAT_NAME[$i]}" = "$1" ] && { printf '%s|%s' "${CAT_DEFAULT[$i]}" "${CAT_PATHS[$i]}"; return; }
    done
}
# procs <name> — the row's process names, space-separated.
procs() {
    local i
    for i in $(cat_indices); do
        [ "${CAT_NAME[$i]}" = "$1" ] && { printf '%s' "${CAT_PROCS[$i]}" | tr '\n' ' '; return; }
    done
}

assert_eq "0|$CL/claude-code/2.1.304" "$(row "Older Claude Code builds in Claude desktop")" \
    "older Claude Code builds: every build but the newest, unchecked"
assert_eq "Claude" "$(procs "Older Claude Code builds in Claude desktop")" \
    "older Claude Code builds: warn while Claude desktop runs"

assert_eq "1|$ZED/languages
$ZED/node
$ZED/prettier
$ZED/hang_traces
$HOME/Library/Caches/Zed
$HOME/Library/Logs/Zed" "$(row "Zed language servers & logs")" "Zed: its downloads, logs & traces, pre-selected"
assert_eq "zed" "$(procs "Zed language servers & logs")" "Zed: warn while Zed runs"

assert_eq "0|$GC/OptGuideOnDeviceModel
$GC/SODA
$GC/SODALanguagePacks
$GC/screen_ai" "$(row "Chrome on-device AI models")" "Chrome models: Gemini Nano, SODA & Screen AI, unchecked"

assert_eq "0|$AER/videos" "$(row "Downloaded aerial wallpapers")" "aerials: the videos only, unchecked"

assert_eq "1|$AS/Code/agent-host/sdk-cache
$EDA/Cache
$EDA/Code Cache
$EDA/GPUCache
$EDA/Service Worker/CacheStorage" "$(row "Electron / Chromium app caches")" \
    "Electron caches: VS Code's agent SDK and EasyEDA's Chromium caches"

assert_eq "1|$HOME/Library/Caches/com.google.GeminiMacOS/Updates" "$(row "App updater staging caches")" \
    "updater caches: Gemini's downloaded update"

assert_eq "1|$HOME/.wrangler/logs
$HOME/Library/Preferences/.wrangler/logs" "$(row "Cloud CLI caches & logs")" \
    "cloud CLI caches: wrangler's logs in both of its homes"

# Nothing any row offers may be state the apps above keep for the user.
t_never=""
for i in $(cat_indices); do
    while IFS= read -r p; do
        case "$p" in
            "$CL"/claude-code/2.1.308*|"$CL"/claude-code-vm*|\
            "$ZED"/db*|"$ZED"/extensions*|"$ZED"/threads*|"$ZED"|"$HOME"/.config/zed*|\
            "$GC"/Default*|"$GC"|"$AER"/manifest*|"$AER"/thumbnails*|"$AER"|"$AS"/com.apple.wallpaper/Store*|\
            "$AS"/Code/agent-host/local-endpoint*|"$AS"/Code/agentSessionData*|\
            "$EDA"/Local\ Storage*|"$EDA"/IndexedDB*|"$EDA"/Service\ Worker/ScriptCache*|"$EDA"|\
            "$HOME"/Library/Caches/com.google.GeminiMacOS/Cache.db|"$HOME"/.wrangler/config*)
                t_never="$t_never ${p#$HOME/}" ;;
        esac
    done <<EOF
${CAT_PATHS[$i]}
EOF
done
assert_eq "" "$t_never" "no row offers settings, sessions, site data or the newest Claude Code build"

test_summary
