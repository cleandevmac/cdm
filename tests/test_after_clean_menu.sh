#!/bin/bash
# The post-clean prompt (after_clean_menu) and the donate action behind its `b`
# key (open_donate).
#
# What the assertions below are shaped around:
#
#   * the return value IS the control flow: the main loop rescans on 0 and exits
#     on 1, so every row here asserts the status, never the prompt text. Quit is
#     the default and has to be reached by every path that is not an explicit
#     `r` — an unknown key, Esc, and a closed stdin included. Nothing is at risk
#     in either direction (the clean has already run), so the failure worth
#     defending against is the loop that will not let go: a prompt that re-asks
#     on an unrecognized key, or one that spins forever on EOF.
#   * keys are read from fd 3, exactly as they are in the real run — cdm never
#     reads fd 0, which under `curl | bash` is the script itself. Each call
#     below redirects fd 3 from a here-document, so this exercises the same
#     read the tool uses rather than a stand-in.
#   * `b` is the one key that does NOT answer the question, so it acts and asks
#     again. The two-key fixtures are what pin that: feed `b` then `q` and the
#     prompt must consume both. It is `b` and not `d` because the main menu
#     already spends `d` on details — asserted below, since the collision is
#     exactly the sort of thing that creeps back in.
#   * open(1) is shadowed by a function that records its argument. That is the
#     only seam here — the alternative is a test that opens a payment page in
#     the developer's browser — and it pins the thing that matters: the URL
#     handed over is DONATE_URL, unmodified.
#   * the donate line is the tool's one ask for money and cdm keeps it to two
#     places (--help, and a clean that freed something). This prompt is inside
#     the second, so `q` and EOF must not open anything: asserted by the log
#     staying empty, not just by the return status.

. "$(dirname "$0")/lib.sh"

# ---- local helpers ---------------------------------------------------------

T_OPEN_LOG="$HOME/open.log"
: > "$T_OPEN_LOG"

# Shadows open(1) for the rest of this file. Records what it was asked to open,
# one line per call, and reports success as the real one would.
open() { printf '%s\n' "$*" >> "$T_OPEN_LOG"; return 0; }

# t_menu <keys> — run the prompt with <keys> on fd 3, swallow the prompt text,
# echo its exit status. The keys go in as one string: each `read -n 1` takes the
# next character, so "bq" is two answers.
t_menu() {
    local rc
    after_clean_menu 3<<EOF >/dev/null 2>&1
$1
EOF
    rc=$?
    echo "$rc"
}

# t_menu_out <keys> — the same, but echoing what the prompt PRINTED, with the
# escapes stripped, so a row can assert on visible text.
t_menu_out() {
    after_clean_menu 3<<EOF 2>&1 | sed "s/$(printf '\033')\[[0-9;]*m//g"
$1
EOF
}

t_opened() { cat "$T_OPEN_LOG"; }
t_reset()  { : > "$T_OPEN_LOG"; }

# ---- the three answers -----------------------------------------------------

assert_eq "0" "$(t_menu r)" "r rescans"
assert_eq "0" "$(t_menu R)" "R rescans too"
assert_eq "1" "$(t_menu q)" "q quits"
assert_eq "1" "$(t_menu Q)" "Q quits too"

# Enter is the default answer and reaches `read -n 1` as the empty line
# delimiter, never as a literal CR — so an empty key IS Enter, the same way the
# main menu reads it.
assert_eq "1" "$(t_menu '')" "Enter takes the default (quit)"

# Anything unrecognized quits rather than re-asking. The clean has already run,
# so there is nothing to lose by leaving, and a prompt that will not accept an
# answer is worse than one that takes the wrong one.
assert_eq "1" "$(t_menu x)" "an unrecognized key takes the default (quit)"
assert_eq "1" "$(t_menu $'\033')" "Esc takes the default (quit)"

# No answer at all: a closed stdin, i.e. no terminal or a Ctrl-D. It must return,
# not spin — this is the case that would hang a piped run forever.
assert_eq "1" "$(after_clean_menu 3</dev/null >/dev/null 2>&1; echo $?)" \
    "EOF on fd 3 takes the default (quit)"

# Nothing above went anywhere near the browser.
assert_eq "" "$(t_opened)" "answering the prompt never opens anything on its own"

# ---- b: acts, then asks again ----------------------------------------------

t_reset
assert_eq "1" "$(t_menu bq)" "b opens the link, then the prompt asks again"
assert_eq "$DONATE_URL" "$(t_opened)" "b hands DONATE_URL to open(1), unmodified"

t_reset
assert_eq "0" "$(t_menu br)" "b then r opens the link and rescans"
assert_eq "$DONATE_URL" "$(t_opened)" "one keypress, one open"

# It really does keep asking — three donates and a quit is four reads, and a
# prompt that returned after the first would consume only one.
t_reset
assert_eq "1" "$(t_menu bbbq)" "b can be pressed repeatedly"
assert_eq "$DONATE_URL
$DONATE_URL
$DONATE_URL" "$(t_opened)" "each b opens the link once"

# EOF right after a b: the prompt has re-asked and there is nothing left to
# read, which is the default again rather than a spin.
t_reset
assert_eq "1" "$(t_menu b)" "b followed by EOF takes the default (quit)"
assert_eq "$DONATE_URL" "$(t_opened)" "the b before the EOF still acted"

# The letter this prompt does NOT use, and the reason: the main menu already
# spends `d` on details ("show the exact paths behind an item"), and one letter
# meaning two things across the tool's two prompts is a keymap that never
# recovers. Here `d` is simply not a key — it takes the default like any other
# unrecognized one, and it opens nothing.
t_reset
assert_eq "1" "$(t_menu d)" "d is not the donate key — it takes the default (quit)"
assert_eq "" "$(t_opened)" "d opens nothing"

# ---- open_donate: the fallback when open(1) is unavailable -----------------
#
# Piped into a container, over ssh, or on a Mac where the handler is broken,
# open(1) fails. The URL still has to reach the user as text — it is the entire
# point of the keypress.
t_reset
assert_eq "$DONATE_URL" "$(open_donate | sed "s/$(printf '\033')\[[0-9;]*m//g" | awk '{print $NF}')" \
    "a successful open still shows the URL"

# Shadow the shadow: open(1) refuses.
open() { return 1; }
t_reset
t_out=$(open_donate | sed "s/$(printf '\033')\[[0-9;]*m//g")
assert_eq "  $DONATE_URL" "$t_out" "a failed open prints the URL instead"
assert_eq "" "$(t_opened)" "the failing open recorded nothing"

test_summary
