#!/bin/bash
# The orphan scan's two halves that decide which apps are gone, run against a fake
# home and a fake LaunchServices dump. Found by deleting VS Code: none of its 1.3 GB
# was offered, for two separate reasons, and each is pinned here.
#
#   * lsr_live — the installed set read every bundle id in `lsregister -dump`,
#     including records of apps in the Trash or gone from disk, so a deleted app
#     still counted as installed. A record is dropped only on LaunchServices' own
#     evidence; an app on an unplugged disk ("not mounted") stays installed.
#   * register_orphans' "apps" — VS Code keeps its data in Application Support/Code
#     and ~/.vscode, names no bundle-id scan can match. orphans.json maps an id to
#     such paths. A path two apps list stays while either is installed, and the id
#     decides everything, so a malformed one must never offer anything. Folders a
#     command-line tool also uses are "optional": a row of their own, with a note.
#
# see docs/DESIGN.md#dead-launchservices-records, docs/DESIGN.md#orphan-app-paths

. "$(dirname "$0")/lib.sh"

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0; }
put() { mkdir -p "$(dirname "$1")"; echo x > "$1"; }
SEP='--------------------------------------------------------------------------------'

# ---- lsr_live: which LaunchServices records still count ---------------------

cat > "$HOME/dump.txt" <<EOF
Checking data integrity...
header.mentions.com.example.header
$SEP
bundle id:                  Live (0x10)
path:                       /Applications/Live.app (0x11)
identifier:                 com.example.live
mount state:                mounted
$SEP
bundle id:                  Trashed (0x20)
path:                       /Users/me/.Trash/Trashed.app (0x21)
identifier:                 com.example.trashed
$SEP
bundle id:                  OnUsb (0x28)
path:                       /Volumes/USB/.Trashes/501/OnUsb.app (0x29)
identifier:                 com.example.usbtrash
$SEP
bundle id:                  Gone (0x30)
Bundle node not found on disk: Error Domain=NSOSStatusErrorDomain Code=-43
mount state:                mounted
path:                       /Applications/Gone.app (0x31)
identifier:                 com.example.gone
$SEP
bundle id:                  Unplugged (0x40)
Bundle node not found on disk: Error Domain=NSOSStatusErrorDomain Code=-43
mount state:                not mounted
path:                       /Volumes/Ext/Unplugged.app (0x41)
identifier:                 com.example.unplugged
$SEP
handlerpref id:             public.json (0x4c)
all roles:                  com.example.handler
$SEP
bundle id:                  Notes (0x50)
path:                       /Applications/Obsidian.app (0x51)
identifier:                 md.obsidian
$SEP
bundle id:                  Last (0x60)
path:                       /Users/me/.Trash/Last.app (0x61)
identifier:                 com.example.last
EOF

LIVE=$(lsr_live "$HOME/ids.txt" < "$HOME/dump.txt")
IDS=$(cat "$HOME/ids.txt" 2>/dev/null)
has() { case "$NL$1$NL" in *"$2"*) echo yes ;; *) echo no ;; esac; }

assert_eq yes "$(has "$LIVE" com.example.live)"      "a live record is kept"
assert_eq yes "$(has "$LIVE" com.example.header)"    "the text before the first record is kept"
assert_eq no  "$(has "$LIVE" com.example.trashed)"   "an app in ~/.Trash is gone"
assert_eq no  "$(has "$LIVE" com.example.usbtrash)"  "an app in a volume's .Trashes is gone"
assert_eq no  "$(has "$LIVE" com.example.gone)"      "not found on disk, on a mounted volume, is gone"
assert_eq yes "$(has "$LIVE" com.example.unplugged)" "an app on an unplugged disk stays installed"
assert_eq no  "$(has "$LIVE" com.example.handler)"   "a default-app choice proves nothing"
assert_eq no  "$(has "$LIVE" com.example.last)"      "the last record is judged too"
assert_eq "com.example.live
com.example.unplugged
md.obsidian" "$IDS" "live identifiers are listed, one-dot ids included"

# A dump that ends on a live record, with no separator after it.
printf 'bundle id: Solo (0x1)\nidentifier: com.example.solo\n' > "$HOME/solo.txt"
rm -f "$HOME/ids.txt"
assert_eq yes "$(has "$(lsr_live "$HOME/ids.txt" < "$HOME/solo.txt")" com.example.solo)" \
    "a live last record is kept"
assert_eq com.example.solo "$(cat "$HOME/ids.txt" 2>/dev/null)" "and its identifier listed"

# ---- register_orphans: the "apps" map ---------------------------------------

AS="$HOME/Library/Application Support"
INSTALLED="$SCAN_DIR/installed.txt"
ORPH_LOC_PATH=("~/Library/Preferences"); ORPH_LOC_STRIP=(".plist")
SKIP_PREFIXES=(); SHARED_COMPONENTS=()

# app <id> <name> <path...> — one "apps" entry, as parse_orphan_stream stores it.
# A path written "opt:<path>" goes to the optional list; NOTE is the note.
app() {
    local n=${#ORPH_APP_ID[@]} id="$1" name="$2" p paths="" opt=""
    shift 2
    for p in "$@"; do
        case "$p" in
            opt:*) opt="${opt:+$opt$NL}${p#opt:}" ;;
            *) paths="${paths:+$paths$NL}$p" ;;
        esac
    done
    ORPH_APP_ID[$n]="$id"; ORPH_APP_NAME[$n]="$name"; ORPH_APP_NOTE[$n]="${NOTE:-}"
    ORPH_APP_PATHS[$n]="$paths"; ORPH_APP_OPT[$n]="$opt"
}
apps_reset() { ORPH_APP_ID=(); ORPH_APP_NAME=(); ORPH_APP_NOTE=(); ORPH_APP_PATHS=(); ORPH_APP_OPT=()
               ORPH_KEEP_PATH=(); ORPH_KEEP_CMD=(); }
run_orphans() { reset_cats; printf '%s\n' "$@" > "$INSTALLED"; register_orphans; }
row_of() {  # the paths of the row named <name>, or "none"
    local i=0
    while [ "$i" -lt "$N" ]; do
        [ "${CAT_NAME[$i]}" = "$1" ] && { printf '%s' "${CAT_PATHS[$i]}"; return; }
        i=$((i + 1))
    done
    printf none
}

put "$AS/Code/User/settings.json"
put "$HOME/.vscode/extensions/ext.json"
put "$HOME/.vscode-shared/sharedStorage/state.vscdb"
put "$AS/Code - Insiders/User/settings.json"
put "$HOME/Library/Preferences/com.microsoft.VSCode.plist"
mkdir -p "$HOME/.empty-app"
put "$HOME/Documents/notes.txt"
put "$AS/obsidian/obsidian.json"
put "$AS/Sublime Text/Local/Session.sublime_session"
put "$HOME/.abs-only/x"

apps_reset
app com.microsoft.VSCode "Visual Studio Code" "~/Library/Application Support/Code" "~/.vscode" "~/.vscode-shared" "~/.empty-app"
app com.microsoft.VSCodeInsiders "Visual Studio Code - Insiders" "~/Library/Application Support/Code - Insiders" "~/.vscode-shared"

run_orphans com.example.other
assert_eq "$HOME/Library/Preferences/com.microsoft.VSCode.plist
$AS/Code
$HOME/.vscode
$HOME/.vscode-shared" "$(row_of "Orphaned: Visual Studio Code")" \
    "a gone app's folders join its bundle-id row; an empty one is left out"
assert_eq "$AS/Code - Insiders" "$(row_of "Orphaned: Visual Studio Code - Insiders")" \
    "a path two gone apps share is offered once, in the first app's row"
assert_eq none "$(row_of "Orphaned: com.microsoft.VSCode")" "the row is named after the app"
case "${CAT_DESC[0]}" in *"'com.microsoft.VSCode'"*) r=yes ;; *) r=no ;; esac
assert_eq yes "$r" "the description still names the bundle id"
assert_eq "trash 0" "${CAT_METHOD[0]} ${CAT_DEFAULT[0]}" "an app row goes to the Trash, unchecked"

run_orphans com.microsoft.VSCode
assert_eq none "$(row_of "Orphaned: Visual Studio Code")" "an installed app's folders are never offered"
assert_eq "$AS/Code - Insiders" "$(row_of "Orphaned: Visual Studio Code - Insiders")" \
    "a shared path stays while one of its apps is installed"

run_orphans com.microsoft.VSCode.helper
assert_eq none "$(row_of "Orphaned: Visual Studio Code")" "a child id that is installed keeps the app"

# Paths a rule must not reach, and ids that must not decide anything. Each bad id
# gets a folder of its own, so one entry cannot hide another, and the check is
# by path: a malformed id would not even survive as a row name.
offered() {  # yes when any row lists <path>
    local i=0
    while [ "$i" -lt "$N" ]; do
        case "$NL${CAT_PATHS[$i]}$NL" in *"$NL$1$NL"*) echo yes; return ;; esac
        i=$((i + 1))
    done
    echo no
}
for d in .bad-space .bad-glob .bad-nodots .bad-leading .bad-shared; do put "$HOME/$d/x"; done
apps_reset
app com.example.paths "Paths" "$HOME/.abs-only" ".vscode" "~/Documents" "~/.vscode" "~/.vscode"
app "com.bad id.x" "Bad" "~/.bad-space" "~/.bad-shared"
app "com.bad.*" "Glob" "~/.bad-glob"
app nodots "No dots" "~/.bad-nodots"
app ".leading" "Leading dot" "~/.bad-leading"
app com.example.shared "Shared" "~/.bad-shared"
run_orphans com.example.other
assert_eq "$HOME/.vscode" "$(row_of "Orphaned: Paths")" \
    "only ~/ paths count, a protected folder is never listed, and a path is listed once"
assert_eq no "$(offered "$HOME/.bad-space")"   "an id with a space is never offered"
assert_eq no "$(offered "$HOME/.bad-glob")"    "an id with a glob is never offered"
assert_eq no "$(offered "$HOME/.bad-nodots")"  "an id without a dot is never offered"
assert_eq no "$(offered "$HOME/.bad-leading")" "an id that starts with a dot is never offered"
assert_eq no "$(offered "$HOME/.bad-shared")"  "a malformed entry's paths count as kept"

# A path the bundle-id scan already found is listed once; and the map works with
# no scan locations at all.
apps_reset
app com.microsoft.VSCode "Visual Studio Code" "~/Library/Preferences/com.microsoft.VSCode.plist"
run_orphans com.example.other
assert_eq "$HOME/Library/Preferences/com.microsoft.VSCode.plist" "$(row_of "Orphaned: Visual Studio Code")" \
    "a path found twice is listed once"
ORPH_LOC_PATH=(); ORPH_LOC_STRIP=()
apps_reset
app com.microsoft.VSCode "Visual Studio Code" "~/.vscode"
run_orphans com.example.other
assert_eq "$HOME/.vscode" "$(row_of "Orphaned: Visual Studio Code")" "apps are scanned with no locations configured"
ORPH_LOC_PATH=("~/Library/Preferences"); ORPH_LOC_STRIP=(".plist")

# One-dot ids, and a vendor namespace standing in for a versioned id.
apps_reset
app md.obsidian "Obsidian" "~/Library/Application Support/obsidian"
app com.sublimetext "Sublime Text" "~/Library/Application Support/Sublime Text"
run_orphans com.example.other
assert_eq "$AS/obsidian" "$(row_of "Orphaned: Obsidian")" "a one-dot id is offered once gone"
assert_eq "$AS/Sublime Text" "$(row_of "Orphaned: Sublime Text")" "a namespace with nothing under it is gone"
run_orphans md.obsidian com.sublimetext.4
assert_eq none "$(row_of "Orphaned: Obsidian")" "a one-dot id that is installed is kept"
assert_eq none "$(row_of "Orphaned: Sublime Text")" "a namespace is kept while any version under it is installed"

# ---- optional paths: a row of their own -------------------------------------
#
# ~/.docker is also the docker CLI's (OrbStack, Colima). Once Docker Desktop is
# gone it is offered, but apart from the app's own folders and with its note.
put "$AS/Docker Desktop/settings.json"
put "$HOME/.docker/config.json"
put "$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
apps_reset
NOTE="The docker CLI's settings." app com.docker.docker "Docker Desktop" \
    "~/Library/Application Support/Docker Desktop" "opt:~/Library/Containers/com.docker.docker" "opt:~/.docker"
NOTE="" app com.example.cli "Docker CLI" "opt:~/.docker"
run_orphans com.example.other
assert_eq "$AS/Docker Desktop" "$(row_of "Orphaned: Docker Desktop")" "optional paths stay out of the app's own row"
assert_eq "$HOME/Library/Containers/com.docker.docker
$HOME/.docker" "$(row_of "Orphaned: Docker Desktop (optional)")" "they get a row of their own"
i=0; while [ "$i" -lt "$N" ] && [ "${CAT_NAME[$i]}" != "Orphaned: Docker Desktop (optional)" ]; do i=$((i + 1)); done
case "${CAT_DESC[$i]:-}" in *"The docker CLI's settings."*) r=yes ;; *) r=no ;; esac
assert_eq yes "$r" "the optional row says why, from the note"
assert_eq "trash 0" "${CAT_METHOD[$i]:-} ${CAT_DEFAULT[$i]:-}" "the optional row goes to the Trash, unchecked"
assert_eq none "$(row_of "Orphaned: Docker CLI (optional)")" "an optional path shared by two gone apps is offered once"
run_orphans com.example.cli
assert_eq "$HOME/Library/Containers/com.docker.docker" "$(row_of "Orphaned: Docker Desktop (optional)")" \
    "an optional path stays while another app listing it is installed"
run_orphans com.docker.docker
assert_eq none "$(row_of "Orphaned: Docker Desktop (optional)")" "nothing optional is offered while the app is installed"

# ---- a command still on PATH keeps its folder --------------------------------
#
# The case that found this: Docker Desktop gone, OrbStack installed, and its
# docker reads ~/.docker. A folder named in keptByCommand stays while any of its
# commands is on PATH, whichever app lists it; the app's own VM disk does not.
mkdir -p "$HOME/bin"
printf '#!/bin/sh\n' > "$HOME/bin/cdm-test-cli"; chmod +x "$HOME/bin/cdm-test-cli"
ln -s "$HOME/no-such-target" "$HOME/bin/cdm-test-dangling"
apps_reset
NOTE="The docker CLI's settings." app com.docker.docker "Docker Desktop" \
    "~/Library/Application Support/Docker Desktop" "opt:~/Library/Containers/com.docker.docker" "opt:~/.docker"
ORPH_KEEP_PATH=("~/.docker" "~/.docker"); ORPH_KEEP_CMD=("cdm-no-such-cli" "cdm-test-cli")
PATH="$HOME/bin:$PATH" run_orphans com.example.other
assert_eq "$HOME/Library/Containers/com.docker.docker" "$(row_of "Orphaned: Docker Desktop (optional)")" \
    "a folder stays while one of its commands is on PATH; the app's own disk is still offered"
ORPH_KEEP_CMD=("cdm-no-such-cli" "cdm-test-dangling")
PATH="$HOME/bin:$PATH" run_orphans com.example.other
assert_eq "$HOME/Library/Containers/com.docker.docker
$HOME/.docker" "$(row_of "Orphaned: Docker Desktop (optional)")" \
    "a command left as a dangling link, or missing, keeps nothing"

# ---- a folder per version ----------------------------------------------------
#
# JetBrains keeps PyCharm2025.1, PyCharm2025.2 … and PyCharm CE beside them as
# PyCharmCE2025.1. <Product>[[:digit:]]* reaches every version of one product
# and never the other, and the EAP build, under its own id, keeps the same folders.
JB="$AS/JetBrains"
put "$JB/PyCharm2025.1/options/ide.xml"
put "$JB/PyCharm2025.2/options/ide.xml"
put "$JB/PyCharmCE2025.1/options/ide.xml"
put "$JB/consentOptions/accepted"
apps_reset
app com.jetbrains.pycharm "PyCharm" "~/Library/Application Support/JetBrains/PyCharm[[:digit:]]*"
app com.jetbrains.pycharm-EAP "PyCharm EAP" "~/Library/Application Support/JetBrains/PyCharm[[:digit:]]*"
run_orphans com.example.other
assert_eq "$JB/PyCharm2025.1
$JB/PyCharm2025.2" "$(row_of "Orphaned: PyCharm")" "every version of the product, and not PyCharm CE's"
run_orphans com.jetbrains.pycharm-EAP
assert_eq none "$(row_of "Orphaned: PyCharm")" "an installed EAP build keeps the release's folders"

# ---- the shipped orphans.json ----------------------------------------------
#
# Parsed the way cdm parses it, then held to the rules each entry must meet.
reset_cats
apps_reset
parse_orphan_stream "$CDM_ROOT/rules/orphans.json"
assert_ok "orphans.json lists apps" [ "${#ORPH_APP_ID[@]}" -gt 10 ]
# check_path <path> — the rules every shipped path meets, optional or not.
check_path() {
    case "$1" in
        "~/"*'[[:digit:]]*') g="${1%\[\[:digit:\]\]\*}"
            case "$g" in *'*'*|*'?'*|*'['*) bad="$bad glob:$1" ;; esac ;;
        "~/"*'*'*|"~/"*'?'*|"~/"*'['*) bad="$bad glob:$1" ;;
        "~/"?*) : ;;
        *) bad="$bad notilde:$1" ;;
    esac
    # is_safe_target judges only what exists, so lay the path out first.
    m="$(expand_tilde "${1%\[\[:digit:\]\]\*}")1"
    case "$1" in *'[[:digit:]]*') : ;; *) m=$(expand_tilde "$1") ;; esac
    mkdir -p "$m" 2>/dev/null
    is_safe_target "$m" || bad="$bad unsafe:$1"
}
bad=""; i=0
while [ "$i" -lt "${#ORPH_APP_ID[@]}" ]; do
    looks_like_app_id "${ORPH_APP_ID[$i]}" || bad="$bad id:${ORPH_APP_ID[$i]}"
    [ -n "${ORPH_APP_NAME[$i]}" ] || bad="$bad noname:${ORPH_APP_ID[$i]}"
    if [ -n "${ORPH_APP_OPT[$i]}" ] && [ -z "${ORPH_APP_NOTE[$i]}" ]; then bad="$bad nonote:${ORPH_APP_ID[$i]}"; fi
    while IFS= read -r p; do
        [ -n "$p" ] && check_path "$p"
    done <<EOF
${ORPH_APP_OPT[$i]}
EOF
    while IFS= read -r p; do
        check_path "$p"
        # Folders a command-line tool or a vendor's other products also use
        # belong in "optional", never in "paths".
        case "$p" in
            "~/.docker"|"~/.ollama"|"~/.codex"|"~/.android"|"~/.claude"|"~/.cursor"|"~/.gemini"|"~/.kiro") bad="$bad shared:$p" ;;
            "~/Library/Application Support/JetBrains"|"~/Library/Application Support/Google") bad="$bad shared:$p" ;;
            "~/Library/Android"*|"~/.local/share/containers") bad="$bad shared:$p" ;;
            "~/Library/Containers/"*|"~/Library/Group Containers/"*) bad="$bad sandbox:$p" ;;
        esac
    done <<EOF
${ORPH_APP_PATHS[$i]}
EOF
    i=$((i + 1))
done
# Every keptByCommand folder is one some app offers as optional, or it guards nothing.
all_opt=""; i=0
while [ "$i" -lt "${#ORPH_APP_ID[@]}" ]; do all_opt="$all_opt$NL${ORPH_APP_OPT[$i]}"; i=$((i + 1)); done
i=0
while [ "$i" -lt "${#ORPH_KEEP_PATH[@]}" ]; do
    case "$all_opt$NL" in *"$NL${ORPH_KEEP_PATH[$i]}$NL"*) : ;; *) bad="$bad unused-keep:${ORPH_KEEP_PATH[$i]}" ;; esac
    case "${ORPH_KEEP_CMD[$i]}" in ''|*[!a-z0-9-]*) bad="$bad cmd:${ORPH_KEEP_CMD[$i]}" ;; esac
    i=$((i + 1))
done
assert_ok "orphans.json names commands that keep folders" [ "${#ORPH_KEEP_PATH[@]}" -gt 0 ]
assert_eq "" "$bad" "every shipped entry has a sound id, a name, safe ~/ paths and a note for optional ones"
assert_eq "~/Library/Application Support/Code
~/.vscode
~/.vscode-shared" "${ORPH_APP_PATHS[0]}" "VS Code's entry reaches its data folders"

test_summary
