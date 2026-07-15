#!/bin/bash
# parse_json_file (cdm:318) — the JXA JSON parser and the flat line protocol it
# emits. The layout is documented at cdm:306-317; this file pins it.
#
# The subtlety, and the reason this file exists: the fields are separated by US
# (\x1f), NOT by tab. That looks like an arbitrary taste call and is not. Tab is
# an IFS *whitespace* character, so bash `read` folds runs of it together and
# strips it from both ends of the line — which means a tab-delimited record
# would silently LOSE its empty fields. `icon` is optional in every rule file,
# so a category that omits it emits an empty second field; under tab, `read`
# would collapse that field and shift the name into the icon column, the method
# into the name column, and so on down the record. US is not IFS whitespace, so
# `read` preserves every field exactly as emitted, empty or not. The
# omitted-icon fixture below is the headline test here, and the counterfactual
# next to it spells out what the other byte would have cost.
#
# The other trap is the inverse one: because tab is not the separator, a tab (or
# a space) appearing *inside* a field is ordinary data and must survive the
# round trip untouched. Both are asserted on the same record.
#
# Every fixture is read back with the exact idiom the real consumers use —
# `IFS=$'\037' read -r ...` (parse_pattern_stream, cdm:567; parse_orphan_stream,
# cdm:586) — so what is under test is the protocol *as consumed*, not merely as
# printed.
#
# This shells out to osascript once per fixture, which is slow (~100ms each), so
# the fixtures are few and each covers as much of the layout as it honestly can.

. "$(dirname "$0")/lib.sh"

US=$'\037'
TAB=$'\t'

# ---- helpers ---------------------------------------------------------------

# rec <n> <output> — the n'th line of a captured parse_json_file output. $2 is
# passed as a printf *argument*, never as its format, so US bytes, backslashes
# and % in the data are inert.
rec() { printf '%s\n' "$2" | sed -n "$1p"; }

# read_c_record <line> — split one record exactly the way parse_pattern_stream
# does (cdm:557-569): peel the type off at the first US, then field-split the
# remainder with IFS=US via a heredoc.
R_TYP=""; R1=""; R2=""; R3=""; R4=""; R5=""; R6=""
read_c_record() {
    local line="$1" rest
    R_TYP="${line%%$US*}"
    rest="${line#*$US}"
    IFS=$US read -r R1 R2 R3 R4 R5 R6 <<EOF
$rest
EOF
}

# count_byte <byte> <string> — how many times <byte> occurs in <string>.
count_byte() { printf '%s' "$2" | tr -dc "$1" | wc -c | tr -d ' '; }

# emits_err <file> — true when parse_json_file emits an ERR record. Used as a
# predicate so a hang shows up as a hung runner rather than a silent pass.
emits_err() {
    local line
    while IFS= read -r line; do
        case "$line" in "ERR$US"*) return 0 ;; esac
    done < <(parse_json_file "$1")
    return 1
}

# ---- fixtures --------------------------------------------------------------

# Well formed, and modelled on the real schema: the scan block from
# rules/project-junk.json, a kind-less paths category from rules/dev-caches.json,
# a kind:project one, and a kind:container one from rules/containers.json. One
# osascript call covers every record type in the documented layout.
cat > "$HOME/good.json" <<'EOF'
{
  "title": "Fixture — well-formed",
  "_comment": "Keys the parser does not know are ignored, exactly like the real files' _comment.",
  "scan": {
    "roots": ["~/code", "~/work"],
    "prune": ["node_modules", ".git"],
    "maxDepth": 8,
    "maxRepos": 400
  },
  "categories": [
    {
      "icon": "A",
      "name": "Cache one",
      "method": "rm",
      "default": true,
      "desc": "first desc",
      "paths": ["~/Library/Caches/one", "~/Library/Caches/two"]
    },
    {
      "kind": "project",
      "icon": "B",
      "name": "Build dirs",
      "method": "rm",
      "default": false,
      "desc": "second desc",
      "dirs": ["dist", "build"]
    },
    {
      "kind": "container",
      "icon": "C",
      "name": "Engines",
      "method": "prune",
      "default": false,
      "desc": "third desc",
      "engines": ["docker", "podman"]
    }
  ]
}
EOF

# The headline. Three categories, each omitting something:
#   1. no icon           — the empty field the whole protocol is built around,
#                          and no desc either, so the record also ends empty.
#   2. no icon, no desc, no method, no default, no kind — every default fires.
#   3. everything present, but the name and desc carry a literal tab and the
#      path a literal space — data that must NOT be treated as structure.
# The em dash in a desc is deliberate: every real rule desc has one.
printf '%s\n' \
'{' \
'  "categories": [' \
'    { "name": "No icon here", "method": "trash", "default": true, "desc": "why — an em dash" },' \
'    { "name": "Bare minimum" },' \
'    { "icon": "🔨", "name": "Has\ttab", "method": "rm", "default": false,' \
'      "desc": "two words and\ta tab", "paths": ["~/a b/c"] }' \
'  ]' \
'}' > "$HOME/noicon.json"

# Modelled on rules/index.json + rules/orphans.json. The first location omits
# "strip", which in the real orphans.json is the common case — an empty field in
# TRAILING position, the one `read` is most eager to drop.
cat > "$HOME/manifest.json" <<'EOF'
{
  "patternFiles": ["a.json", "b.json"],
  "orphanConfig": "orphans.json",
  "locations": [
    { "path": "~/Library/Application Support" },
    { "path": "~/Library/Preferences", "strip": ".plist" }
  ],
  "skipPrefixes": ["com.apple."],
  "sharedComponents": ["com.example.updater"]
}
EOF

cat > "$HOME/bad.json" <<'EOF'
{ "categories": [ { "name": "unterminated"
EOF

P_GOOD=$(parse_json_file "$HOME/good.json")
P_NOICON=$(parse_json_file "$HOME/noicon.json")
P_MANIFEST=$(parse_json_file "$HOME/manifest.json")

# ---- the documented layout, end to end -------------------------------------
#
# One assertion, whole output, exact bytes: record types, their order (scan
# config first; then per category the C header followed by its own P/D/E rows),
# the defaults the parser fills in, and the separator itself.

assert_eq \
"SR${US}~/code
SR${US}~/work
SPRUNE${US}node_modules
SPRUNE${US}.git
SDEPTH${US}8
SREPOS${US}400
C${US}paths${US}A${US}Cache one${US}rm${US}1${US}first desc
P${US}~/Library/Caches/one
P${US}~/Library/Caches/two
C${US}project${US}B${US}Build dirs${US}rm${US}0${US}second desc
D${US}dist
D${US}build
C${US}container${US}C${US}Engines${US}prune${US}0${US}third desc
E${US}docker
E${US}podman" \
"$P_GOOD" \
"a well-formed file emits exactly the documented records, in order"

# The same records read back through the consumer's idiom.
read_c_record "$(rec 7 "$P_GOOD")"
assert_eq "C"         "$R_TYP"  "category record type"
assert_eq "paths"     "$R1"     "kind"
assert_eq "A"         "$R2"     "icon"
assert_eq "Cache one" "$R3"     "name"
assert_eq "rm"        "$R4"     "method"
assert_eq "1"         "$R5"     "default:true becomes 1"
assert_eq "first desc" "$R6"    "desc"

read_c_record "$(rec 10 "$P_GOOD")"
assert_eq "project"   "$R1"     "kind is carried verbatim"
assert_eq "0"         "$R5"     "default:false becomes 0"

# ---- THE headline: an omitted icon must not shift the columns --------------
#
# cdm:335 emits `c.icon || ''`, so the icon field is always present and always
# in position 2 — empty when the rule omits it. Because the separator is US and
# not IFS whitespace, `read` hands that empty field to $R2 and leaves every
# later field where it belongs. Drop the icon argument from the emit, or swap
# the separator for a tab, and name/method/default/desc all slide one column
# left; the assertions below are what notices.

NOICON1=$(rec 1 "$P_NOICON")

assert_eq "C${US}paths${US}${US}No icon here${US}trash${US}1${US}why — an em dash" \
    "$NOICON1" "omitted icon emits an EMPTY field, not a missing one"

assert_eq "6" "$(count_byte "$US" "$NOICON1")" \
    "a C record carries 6 US separators even with the icon omitted"

read_c_record "$NOICON1"
assert_eq "C"              "$R_TYP" "omitted icon: record type"
assert_eq "paths"          "$R1"    "omitted icon: kind still defaults to paths"
assert_eq ""               "$R2"    "omitted icon: the icon column is empty"
assert_eq "No icon here"   "$R3"    "omitted icon: name does NOT shift into the icon column"
assert_eq "trash"          "$R4"    "omitted icon: method does NOT shift into the name column"
assert_eq "1"              "$R5"    "omitted icon: default does NOT shift into the method column"
assert_eq "why — an em dash" "$R6"  "omitted icon: desc does NOT shift into the default column"

# Every optional key omitted at once, which also puts an empty field in TRAILING
# position — where a dropped field is hardest to see, because nothing after it
# moves.
NOICON2=$(rec 2 "$P_NOICON")
assert_eq "C${US}paths${US}${US}Bare minimum${US}rm${US}0${US}" \
    "$NOICON2" "all-optional-keys-omitted category still emits all 7 fields"
assert_eq "6" "$(count_byte "$US" "$NOICON2")" \
    "a trailing empty desc is still a field"

read_c_record "$NOICON2"
assert_eq ""             "$R2" "bare category: empty icon"
assert_eq "Bare minimum" "$R3" "bare category: name lands in the name column"
assert_eq "rm"           "$R4" "bare category: method defaults to rm"
assert_eq "0"            "$R5" "bare category: default defaults to 0"
assert_eq ""             "$R6" "bare category: empty desc"

# ---- the counterfactual: what tab would have cost --------------------------
#
# Not a test of cdm — a test of the bash semantics cdm's choice of US rests on,
# and the clearest statement of why the separator is what it is. Take the very
# record above, change ONLY the separator byte to a tab, feed it to the SAME
# reader, and watch the columns slide: the empty icon vanishes and every later
# field arrives one slot to the left. If this ever stops shifting, the comment
# at cdm:308-310 has stopped being true.

REST_TAB=$(printf '%s' "${NOICON1#*$US}" | tr "$US" "$TAB")
K=""; I=""; NM=""; M=""; D=""; S=""
IFS=$TAB read -r K I NM M D S <<EOF
$REST_TAB
EOF
assert_eq "No icon here" "$I"  "counterfactual: under tab, read collapses the empty icon and the NAME lands in the icon column"
assert_eq "trash"        "$NM" "counterfactual: under tab, the METHOD lands in the name column"
assert_eq ""             "$S"  "counterfactual: under tab, the record runs one field short"

# ---- a space and a tab INSIDE a field are data, not structure --------------

NOICON3=$(rec 3 "$P_NOICON")
assert_eq "6" "$(count_byte "$US" "$NOICON3")" \
    "the record's structure is 6 US bytes..."
assert_eq "2" "$(count_byte "$TAB" "$NOICON3")" \
    "...and its 2 tabs are payload, not separators"

read_c_record "$NOICON3"
assert_eq "🔨"                  "$R2" "a multi-byte emoji icon survives the round trip"
assert_eq "Has${TAB}tab"        "$R3" "a literal tab inside a name survives intact"
assert_eq "two words and${TAB}a tab" "$R6" "a field keeps both its spaces and its tab"

assert_eq "P${US}~/a b/c" "$(rec 4 "$P_NOICON")" \
    "a path containing a space is one field"

# ---- manifest / orphan records ---------------------------------------------

assert_eq \
"FILE${US}a.json
FILE${US}b.json
ORPHAN${US}orphans.json
L${US}~/Library/Application Support${US}
L${US}~/Library/Preferences${US}.plist
SKIP${US}com.apple.
SHARED${US}com.example.updater" \
"$P_MANIFEST" \
"a manifest emits FILE/ORPHAN/L/SKIP/SHARED in the documented layout"

# parse_orphan_stream (cdm:586) splits the whole line with IFS=US, type included.
# A location without "strip" is the real orphans.json's common case: the empty
# field is last, so nothing shifts to give it away — $b simply has to be empty
# rather than absent.
OTYP=""; OA=""; OB=""
IFS=$US read -r OTYP OA OB <<EOF
$(rec 4 "$P_MANIFEST")
EOF
assert_eq "L"                             "$OTYP" "location record type"
assert_eq "~/Library/Application Support" "$OA"   "location path keeps its space"
assert_eq ""                              "$OB"   "an omitted strip is an empty field"

IFS=$US read -r OTYP OA OB <<EOF
$(rec 5 "$P_MANIFEST")
EOF
assert_eq "~/Library/Preferences" "$OA" "location path"
assert_eq ".plist"                "$OB" "a present strip lands in the strip column"

# ---- failure modes ---------------------------------------------------------
#
# Both of these must terminate. There is no `timeout` on a stock Mac, so a hang
# hangs the runner — which is the failure signal.

assert_ok   "malformed JSON yields an ERR record"     emits_err "$HOME/bad.json"
assert_fail "well-formed JSON yields no ERR record"   emits_err "$HOME/good.json"

# The message is JavaScriptCore's, so pin only the type and that a reason came
# with it.
BAD_OUT=$(parse_json_file "$HOME/bad.json")
read_c_record "$BAD_OUT"
assert_eq "ERR" "$R_TYP" "malformed JSON: record type"
assert_ok "malformed JSON: ERR carries a message" test -n "$R1"

# A missing file is not an error the caller should have to pre-empt with a -r
# test; the parser reports it in-band, on the same channel as everything else.
assert_ok "a missing file yields an ERR record" emits_err "$HOME/definitely-not-here.json"
assert_eq "ERR${US}could not read file" "$(parse_json_file "$HOME/definitely-not-here.json")" \
    "a missing file yields the documented ERR record"

# ---- the shipped rules must parse ------------------------------------------
#
# The point of this loop: nothing else in the repo catches a syntax error in a
# rules edit. `bash -n cdm` does not read JSON, and the rules are fetched from
# raw main at RUNTIME — a broken one is live for every piped user the moment it
# merges, before any release gate could have seen it. parse_pattern_stream turns
# an ERR into a warning and skips the file (cdm:560), so a stray comma does not
# crash cdm; it silently stops cleaning a whole category. This loop is what
# makes that a test failure instead.

for f in "$CDM_ROOT"/rules/*.json; do
    assert_fail "rules/${f##*/} parses without an ERR record" emits_err "$f"
done

# index.json is the manifest every run starts from; assert its contents rather
# than just its syntax, so a rename of a rule file cannot pass by parsing fine.
IDX=$(parse_json_file "$CDM_ROOT/rules/index.json")
IFS= read -r IDX_LINE <<EOF
$IDX
EOF
read_c_record "$IDX_LINE"
assert_eq "FILE" "$R_TYP" "index.json's first record is a FILE"
assert_ok "every file index.json lists exists" test -r "$CDM_ROOT/rules/$R1"

test_summary
