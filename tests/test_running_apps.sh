#!/bin/bash
# running_selected_apps (cdm) — names the apps that are running AND own a cache
# the user selected, so the confirm can say "quit Chrome first" BEFORE the
# delete instead of after it. Deleting a cache under its own app reclaims
# nothing: Chrome rewrites Code Cache within seconds and the space comes back.
#
# The load-bearing property here is where the app names come from. They are
# rules data (a category's "procs" list), not a table in cdm. The first draft of
# this feature matched category display NAMES in a case statement inside the
# script, which failed two ways: adding a browser meant editing cdm, against the
# promise that cleanup targets are a JSON edit; and renaming a category in JSON
# silently disabled the warning — no error, no failing test, the check just
# stopped existing. The JSON round-trip and rename assertions below are what pin
# that down; see docs/DESIGN.md#running-app-check.

. "$(dirname "$0")/lib.sh"

# Stand in for the real pgrep. cdm calls `pgrep -xq <name>`, and a shell
# function shadows the binary, so the suite decides what is "running" rather
# than asserting against whatever the developer happens to have open — which
# would make every assertion below pass or fail by accident.
# The shim also pins the -x: an exact match is what keeps "Google Chrome" from
# matching the several "Google Chrome Helper" processes that are always alive
# beside it, and every assertion here would still pass without it. Refusing to
# answer unless cdm asked for -x is what gives the suite a grip on that flag,
# which is otherwise the real pgrep's job and untestable from a shim.
FAKE_RUNNING=""
pgrep() {
    local n
    case "$1" in *x*) : ;; *) return 1 ;; esac
    for n; do :; done
    case "$FAKE_RUNNING" in *"|$n|"*) return 0 ;; *) return 1 ;; esac
}

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0
               # load_patterns normally seeds this; these tests drive
               # parse_pattern_stream directly and cdm runs under `set -u`.
               PARSED_OK=0; }

# cat_add <name> <sel> <procs> [kb]
cat_add() {
    CAT_ICON[$N]="x"; CAT_NAME[$N]="$1"; CAT_DESC[$N]="d"; CAT_METHOD[$N]="rm"
    CAT_DEFAULT[$N]=1; CAT_PATHS[$N]="/nope"; CAT_SEL[$N]="$2"; CAT_PROCS[$N]="$3"
    CAT_KB[$N]="${4:-1}"; CAT_PMETHOD[$N]=""; CAT_SUMMARY[$N]=""; N=$((N + 1))
}

# ---- only running + selected apps are named --------------------------------

FAKE_RUNNING="|Google Chrome|Slack|"

reset_cats
cat_add "Browser caches" 1 "Google Chrome"
assert_eq "Google Chrome" "$(running_selected_apps)" "selected + running is named"

reset_cats
cat_add "Browser caches" 0 "Google Chrome"
assert_eq "" "$(running_selected_apps)" "deselected category is not probed"

reset_cats
cat_add "Browser caches" 1 "Vivaldi"
assert_eq "" "$(running_selected_apps)" "selected but not running is silent"

reset_cats
cat_add "Go module cache" 1 ""
assert_eq "" "$(running_selected_apps)" "category with no procs is silent"

# A rule naming an app nobody has installed must stay silent rather than warn.
# This is why a wrong "procs" entry is cheap: it costs a missing warning, never
# a false one.
reset_cats
cat_add "Browser caches" 1 "NoSuchBrowser"
assert_eq "" "$(running_selected_apps)" "unknown app name never matches"

# ---- de-duplication across categories --------------------------------------

# Chrome owns caches in three different categories; selecting all three must
# name it once, not three times.
reset_cats
cat_add "Browser caches" 1 "Google Chrome"
cat_add "Chromium browser profile caches" 1 "Google Chrome"
cat_add "Chrome on-device AI models" 1 "Google Chrome"
assert_eq "Google Chrome" "$(running_selected_apps)" "same app across 3 categories named once"

reset_cats
cat_add "Browser caches" 1 "Google Chrome
Vivaldi"
cat_add "Electron / Chromium app caches" 1 "Slack
Code"
assert_eq "Google Chrome, Slack" "$(running_selected_apps)" "distinct running apps are joined"

# An empty line in a procs list must not become a probe for "".
reset_cats
cat_add "Browser caches" 1 "
Google Chrome

"
assert_eq "Google Chrome" "$(running_selected_apps)" "blank lines in procs are skipped"

# ---- procs survive prune_zero and sort_by_size -----------------------------
#
# CAT_PROCS is index-aligned with CAT_NAME, and both functions rebuild the whole
# category table by copying each parallel array. Miss CAT_PROCS in either and
# the names silently shift onto the wrong rows: cdm would warn about Chrome
# because Slack is running. Nothing about the menu would look wrong.

FAKE_RUNNING="|Vivaldi|"
reset_cats
cat_add "small" 1 "Vivaldi"        1
cat_add "big"   1 "NotRunningApp"  9
sort_by_size
assert_eq "big"   "${CAT_NAME[0]}"  "sort_by_size ordered biggest-first"
assert_eq "Vivaldi" "${CAT_PROCS[1]}" "sort_by_size keeps CAT_PROCS on its row"
assert_eq "Vivaldi" "$(running_selected_apps)" "warning survives a sort"

FAKE_RUNNING="|Vivaldi|"
reset_cats
cat_add "zero"      1 "NotRunningApp" 0
cat_add "survivor"  1 "Vivaldi"       5
prune_zero
assert_eq "1" "$N" "prune_zero dropped the empty category"
assert_eq "Vivaldi" "${CAT_PROCS[0]}" "prune_zero keeps CAT_PROCS on its row"
assert_eq "Vivaldi" "$(running_selected_apps)" "warning survives a prune"

# ---- procs come from the rules, not from cdm -------------------------------
#
# The whole point of the refactor. These go through the real JXA parser, so they
# assert the "procs" JSON key reaches CAT_PROCS end to end.

RULES="$HOME/rules"; mkdir -p "$RULES"
CACHE="$HOME/Library/Caches/FauxBrowser"; mkdir -p "$CACHE"; : > "$CACHE/blob"

write_rule() { # <category-name>
    cat > "$RULES/faux.json" <<JSON
{
  "title": "faux",
  "categories": [
    {
      "icon": "x",
      "name": "$1",
      "method": "rm",
      "default": true,
      "desc": "faux",
      "procs": ["Google Chrome", "Vivaldi"],
      "paths": ["~/Library/Caches/FauxBrowser"]
    }
  ]
}
JSON
}

FAKE_RUNNING="|Vivaldi|"

reset_cats
write_rule "Browser caches"
parse_pattern_stream "$RULES/faux.json"
assert_eq "1" "$N" "rule with procs registered a category"
assert_eq "Google Chrome
Vivaldi" "${CAT_PROCS[0]}" "procs reached CAT_PROCS through the JSON parser"
assert_eq "Vivaldi" "$(running_selected_apps)" "a rule's procs drive the warning"

# The regression that motivated all of this: renaming a category in JSON is a
# rules-only edit and must not disturb the check. Against the case-on-name
# draft, this assertion is the one that fails.
reset_cats
write_rule "Totally Different Name"
parse_pattern_stream "$RULES/faux.json"
assert_eq "Vivaldi" "$(running_selected_apps)" "renaming the category does not disable the warning"

# A category with no "procs" key at all must parse fine and stay silent, since
# that is every other rule in the tree.
reset_cats
cat > "$RULES/faux.json" <<'JSON'
{
  "title": "faux",
  "categories": [
    { "icon": "x", "name": "No procs", "method": "rm", "default": true,
      "desc": "faux", "paths": ["~/Library/Caches/FauxBrowser"] }
  ]
}
JSON
parse_pattern_stream "$RULES/faux.json"
assert_eq "1" "$N" "rule without procs still registers"
assert_eq "" "${CAT_PROCS[0]}" "absent procs key yields empty CAT_PROCS"
assert_eq "" "$(running_selected_apps)" "rule without procs is silent"

# procs must not bleed from one category into the next in the same file.
reset_cats
cat > "$RULES/faux.json" <<'JSON'
{
  "title": "faux",
  "categories": [
    { "icon": "x", "name": "Has procs", "method": "rm", "default": true,
      "desc": "faux", "procs": ["Vivaldi"], "paths": ["~/Library/Caches/FauxBrowser"] },
    { "icon": "x", "name": "Inherits nothing", "method": "rm", "default": true,
      "desc": "faux", "paths": ["~/Library/Caches/FauxBrowser"] }
  ]
}
JSON
parse_pattern_stream "$RULES/faux.json"
assert_eq "2" "$N" "both categories registered"
assert_eq "Vivaldi" "${CAT_PROCS[0]}" "first category kept its procs"
assert_eq "" "${CAT_PROCS[1]}" "procs did not leak into the next category"

test_summary
