#!/bin/bash
# Claude Code's session history, both halves (docs/DESIGN.md#claude-transcripts
# and #claude-history):
#
#   * the "claude-transcripts" rule kind — register_transcripts offers the
#     sessions whose transcript has not changed in idleDays, each <id>.jsonl with
#     its <id>/ folder, for the Trash;
#   * the note under the disk line — claude_history_stats / claude_history_line
#     say how big the history is and print the setting that makes Claude Code
#     age out the transcripts it otherwise keeps forever.
#
# A transcript is the one record of a conversation, so the kind's assertions are
# mostly about what it refuses: a running session (sessions/*.json names it), a
# fresh one, anything whose name is not a session id — auto memory's memory/
# folder above all — and any method but the Trash or a pre-selected row, whatever
# the rule says. The note's are about when it must stay quiet: once the setting
# is there, Claude Code does the work itself.

. "$(dirname "$0")/lib.sh"

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0; }

# age <days> <path...> — set each path's mtime that many days back.
age() {
    local d="$1" t; shift
    t=$(date -v-"${d}"d +%Y%m%d%H%M.%S)
    touch -t "$t" "$@"
}

CL="$HOME/.claude"
P="$CL/projects/-Users-me-app"
Q="$CL/projects/-Users-me-blog"
OLD=11111111-1111-4111-8111-111111111111
OLD2=22222222-2222-4222-8222-222222222222
LIVE=33333333-3333-4333-8333-333333333333
NEW=44444444-4444-4444-8444-444444444444
mkdir -p "$P/$OLD/subagents" "$P/memory" "$Q" "$CL/sessions"
echo '{"entrypoint":"claude-desktop"}' > "$P/$OLD.jsonl"; echo agent > "$P/$OLD/subagents/agent-a.jsonl"
echo t > "$Q/$OLD2.jsonl"
echo t > "$P/$LIVE.jsonl"
echo t > "$P/$NEW.jsonl"
echo note > "$P/memory/MEMORY.md"
echo t > "$P/notes.jsonl"                     # not a session id
echo t > "$P/$OLD.orphaned-20260101-x.jsonl"  # a set-aside copy, not the session
age 45 "$P/$OLD.jsonl" "$Q/$OLD2.jsonl" "$P/$LIVE.jsonl" "$P/notes.jsonl" "$P/$OLD.orphaned-20260101-x.jsonl" "$P/memory" "$P/memory/MEMORY.md"
age 2 "$P/$NEW.jsonl"
printf '{"pid":4242,"sessionId":"%s","entrypoint":"claude-desktop"}\n' "$LIVE" > "$CL/sessions/4242.json"

GLOBS="~/.claude/projects/*"

# ---- register_transcripts ------------------------------------------------------

reset_cats
register_transcripts "💬" "Old transcripts" "D." "$GLOBS" 30
assert_eq 1 "$N" "one row for every old session"
assert_eq "$P/$OLD
$P/$OLD.jsonl
$Q/$OLD2.jsonl" "$(printf '%s\n' "${CAT_PATHS[0]:-}" | LC_ALL=C sort)" \
    "old sessions with their folders; not the running one, the fresh one, memory/ or non-session files"
assert_eq "2 sessions" "${CAT_SUMMARY[0]:-}" "the summary counts sessions, not paths"
assert_eq "trash|0" "${CAT_METHOD[0]:-}|${CAT_DEFAULT[0]:-}" "always the Trash, never pre-selected"

# The rule's method and default are not the kind's to take: a rule that asks for
# rm, pre-selected, still gets the Trash and an unchecked row.
RULES=$(mktemp -d "$HOME/rules.XXXXXX")
cat > "$RULES/t.json" <<'JSON'
{ "categories": [ {
    "kind": "claude-transcripts", "icon": "x", "name": "Old transcripts",
    "method": "rm", "default": true, "idleDays": 30, "desc": "d",
    "candidates": [ "~/.claude/projects/*" ]
} ] }
JSON
reset_cats; PARSED_OK=0
parse_pattern_stream "$RULES/t.json"
assert_eq "trash|0" "${CAT_METHOD[0]:-}|${CAT_DEFAULT[0]:-}" "a rule asking for rm, pre-selected, still gets trash, unchecked"

# The rule's age: at 60 days nothing is old enough.
reset_cats
register_transcripts "💬" "Old transcripts" "D." "$GLOBS" 60
assert_eq 0 "$N" "idleDays 60: a 45-day-old session is kept"

# No usable idleDays: nothing.
reset_cats; register_transcripts "💬" "Old transcripts" "D." "$GLOBS" ""
assert_eq 0 "$N" "no idleDays offers nothing"

# A finished session is no longer listed as running: then it is offered.
rm -f "$CL/sessions/4242.json"
reset_cats
register_transcripts "💬" "Old transcripts" "D." "$GLOBS" 30
assert_eq "3 sessions" "${CAT_SUMMARY[0]:-}" "once its process has gone, the old session is offered too"

# Older cdm: unknown kind, nothing in "paths" — nothing.
sed 's/"kind": "claude-transcripts"/"kind": "some-future-kind"/' "$RULES/t.json" > "$RULES/old.json"
reset_cats; PARSED_OK=0
parse_pattern_stream "$RULES/old.json"
assert_eq 0 "$N" "unknown kind with only 'candidates' registers nothing"

# The shipped rule: unchecked, to the Trash, and the same three sessions.
reset_cats; PARSED_OK=0
parse_pattern_stream "$CDM_ROOT/rules/dev-caches.json"
t_row=""
for i in $(cat_indices); do
    case "${CAT_NAME[$i]}" in "Claude Code transcripts"*) t_row="${CAT_METHOD[$i]}|${CAT_DEFAULT[$i]}|${CAT_SUMMARY[$i]}" ;; esac
done
assert_eq "trash|0|3 sessions" "$t_row" "shipped dev-caches.json: three old sessions, unchecked, to the Trash"

# ---- claude_history_stats / claude_history_line ------------------------------------

# du is faked: a real gigabyte of transcripts is not something to write in a test.
t_du_kb=11117312
du() { printf '%s\t%s\n' "$t_du_kb" "${!#}"; }

assert_ok "old transcripts and no setting: stats succeed" claude_history_stats
claude_history_stats
# Three: the running session's transcript is old too, and Claude Code keeps it;
# notes.jsonl and the set-aside copy are not sessions.
assert_eq "11117312|3|30" "$CLAUDE_HIST_KB|$CLAUDE_OLD_N|$CLAUDE_KEEP_DAYS" "size, sessions past 30 days, the limit"
assert_eq "10.60 GB of session history in ~/.claude/projects, 3 transcripts older than 30 days.
Claude Code keeps Claude Desktop and Cowork sessions at any age; to have it delete them after 30 days too, add \"desktopSessionCleanupPeriodDays\": 30 to ~/.claude/settings.json" \
    "$(claude_history_line)" "the note: how big, how many old, and the exact setting"

# cleanupPeriodDays moves the limit, and the advice with it.
printf '{\n  "theme": "dark",\n  "cleanupPeriodDays" : 40\n}\n' > "$CL/settings.json"
claude_history_stats
assert_eq "3|40" "$CLAUDE_OLD_N|$CLAUDE_KEEP_DAYS" "cleanupPeriodDays 40: 45-day-old transcripts still count"
assert_eq "after 40 days too, add \"desktopSessionCleanupPeriodDays\": 40 to" \
    "$(claude_history_line | grep -o 'after 40 days too, add "desktopSessionCleanupPeriodDays": 40 to')" "the advice uses the user's limit"
printf '{ "cleanupPeriodDays": 50 }\n' > "$CL/settings.json"
assert_fail "cleanupPeriodDays 50: nothing older, no note" claude_history_stats

# Once the setting is there, Claude Code ages them out itself: no note.
printf '{ "desktopSessionCleanupPeriodDays": 30 }\n' > "$CL/settings.json"
assert_fail "desktopSessionCleanupPeriodDays set: no note" claude_history_stats
assert_fail "...and the line stays empty" claude_history_line
rm -f "$CL/settings.json"

# A small history is not worth the line, however old.
t_du_kb=524288
claude_history_stats
assert_fail "under 1 GiB of history: no note" claude_history_line
t_du_kb=1048576
claude_history_stats
assert_ok "exactly 1 GiB: the note" claude_history_line

# CLAUDE_CONFIG_DIR moves everything.
mkdir -p "$HOME/alt/projects/x"; echo t > "$HOME/alt/projects/x/$OLD.jsonl"; age 45 "$HOME/alt/projects/x/$OLD.jsonl"
( CLAUDE_DIR="$HOME/alt"; claude_history_stats; claude_history_line ) > "$HOME/alt.out"
assert_eq "1.00 GB of session history in ~/alt/projects, 1 transcript older than 30 days." "$(head -n 1 "$HOME/alt.out")" \
    "another config dir: its own history, one transcript"
assert_ok "...and its own settings.json" grep -q 'to ~/alt/settings.json$' "$HOME/alt.out"

# ...and it is CLAUDE_CONFIG_DIR, read when cdm loads, that moves it. Sourced
# again in a subshell with CDM_LIB=1, which stops at the hook; the cursor escape
# its exit trap prints is cut off.
t_cd=$( export CLAUDE_CONFIG_DIR="$HOME/alt"; set --; CDM_LIB=1 . "$CDM_BIN" >/dev/null 2>&1; printf '%s\n' "$CLAUDE_DIR" )
assert_eq "$HOME/alt" "$(printf '%s\n' "$t_cd" | head -n 1)" "CLAUDE_CONFIG_DIR sets where the history is read"

# No history at all.
mv "$CL/projects" "$CL/projects.off"
assert_fail "no projects folder: no note" claude_history_stats
mv "$CL/projects.off" "$CL/projects"

test_summary
