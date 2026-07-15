#!/bin/bash
# Static guards on the cdm SOURCE TEXT — the bash 3.2 floor, the printf-format
# rule, the fd-3 rule, and the release shebang. These grep "$CDM_BIN"; they do
# not call a single cdm function, which makes them the odd file out here and
# needs justifying.
#
# CI's only pre-release gate is `bash -n cdm`, run on ubuntu-latest — i.e. bash 5
# validating a bash 3.2 target. That gate provably cannot catch a bash-4 idiom,
# and the bottom of this file proves it behaviourally rather than asserting it.
# Measured on /bin/bash 3.2.57, the floor:
#
#   declare -A m; m[foo]=bar; m[baz]=qux   ->  EXIT 0. "invalid option" on stderr,
#                                              then both keys evaluate as
#                                              arithmetic to index 0, so m[foo]
#                                              and m[baz] are the same slot and
#                                              both read back "qux". Silent
#                                              corruption, zero exit, and `bash -n`
#                                              passes on 3.2 AND on 5 — `declare`
#                                              is a builtin, so its options are a
#                                              runtime concern the parser never
#                                              sees.
#   mapfile -t a < f                       ->  "command not found", script carries on.
#   ${x^^}                                 ->  "bad substitution" at runtime.
#   local -n r=$1                          ->  "invalid option" at runtime.
#   cmd &>> log                            ->  syntax error — the ONLY one of the
#                                              five `bash -n` catches, and only on
#                                              3.2, which is not the bash CI runs.
#
# So for four of the five constructs below there is no gate anywhere in the
# pipeline except this file, and the failure they produce on a user's Mac is a
# wrong answer rather than a crash. That is why these are worth a test file.
#
# The subtlety is the greps themselves. A guard that cannot fire is worse than no
# guard, and the way this one dies is comments: the moment someone documents the
# rule in cdm ("never use declare -A here") the naive grep matches prose and the
# guard gets loosened or deleted. So the greps run over comment-stripped source,
# and the strip is deliberately the most conservative one that works, because the
# two error directions are not symmetric — a false positive is loud and gets
# fixed, a false negative ships bash 4 syntax to every user. It therefore only
# removes (a) lines whose first non-blank character is `#`, which can never be a
# command, and (b) a trailing comment introduced by whitespace-`#`-whitespace.
# Requiring whitespace BEFORE the `#` is what keeps `${s#$num}` and `${line#*$us}`
# (cdm:215, cdm:558) intact — a strip anchored on `#` alone would truncate real
# code and go quiet. Verified against the real cdm: every line the strip touches
# is a genuine trailing comment, and no code line carries ` # ` inside a string.
#
# Line numbers are kept through the strip (grep -n runs first) so a failure names
# the offending cdm line instead of just saying "something matched".

. "$(dirname "$0")/lib.sh"

# ---- helpers ---------------------------------------------------------------

# code_lines — cdm's source with comments removed, each line still prefixed
# "<lineno>:". The prefix is inert for every pattern below (none anchor on ^).
code_lines() {
    grep -n -v '^[[:space:]]*#' "$CDM_BIN" \
        | sed -e 's/[[:space:]]#[[:space:]].*$//' -e 's/[[:space:]]#$//'
}

# code_matching <ere> — offending cdm lines, or nothing. Every guard is written
# as assert_eq "" "$(code_matching ...)" so that a failure prints the actual
# source line as the "got" value.
code_matching() {
    code_lines | grep -E "$1"
}

# ---- bash 4 constructs: must not appear in cdm ------------------------------
#
# Each pattern below was checked to fire on real code before being trusted:
# `declare -A cache`, `local -A m`, `typeset -A t`, `declare -gA g`, `${name^^}`,
# `${name,,}`, `${arr[0]^}`, `mapfile -t l < f`, `readarray -t l < f`,
# `cmd &>> "$LOG"`, `local -n ref=$1` and `declare -n ref2=$1` are all matched,
# while the same words in a comment are not.

# Associative arrays (bash 4). The `-[A-Za-z]*A` tail catches the clustered
# spellings too — `declare -gA`, `declare -Ag` — not just a bare `-A`.
assert_eq "" \
    "$(code_matching '(declare|typeset|local)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*A')" \
    "no associative arrays (declare -A / local -A) — bash 4, and 3.2 exits 0 on it"

# Case modification: ${v^^} ${v^} ${v,,} ${v,} (bash 4). No bash 3.2 expansion
# puts `^` or `,` immediately after a name or a subscript, so this cannot
# collide with a legitimate ${v%%,*} or ${v#...}.
assert_eq "" \
    "$(code_matching '\$\{[!#]?[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(\^|,)')" \
    "no case modification (\${v^^} / \${v,,}) — bash 4"

# mapfile / readarray (bash 4). cdm reads into arrays with `while IFS= read -r`.
assert_eq "" \
    "$(code_matching '(^|[^A-Za-z0-9_./-])(mapfile|readarray)([^A-Za-z0-9_]|$)')" \
    "no mapfile / readarray — bash 4"

# `&>>` — append stdout+stderr (bash 4). Note bash 3.2 DOES support `&>`; it is
# only the appending form that is new, which makes this an easy one to reach for.
assert_eq "" \
    "$(code_matching '&>>')" \
    "no &>> — bash 4 (plain &> is fine and is not flagged)"

# Namerefs (bash 4.3). cdm's whole category model is parallel arrays precisely
# because it cannot have these.
assert_eq "" \
    "$(code_matching '(declare|typeset|local)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*n([[:space:]]|$)')" \
    "no namerefs (local -n / declare -n) — bash 4.3"

# ---- the frame is data, not a format string (cdm:1394, render_menu) ---------
#
# $buf is built from category names and repo paths. `printf "$buf"` would read
# those as a FORMAT: a directory named `ha\nck` emits a real newline (the frame
# outgrows its row budget and the terminal scrolls on every repaint) and one
# named `esc\033[41m` injects escape sequences straight out of a filename.

assert_eq "" \
    "$(code_matching 'printf[[:space:]]+"?\$\{?buf')" \
    "never printf \"\$buf\" — the frame holds filenames, which are not a format"

# The safe form must actually be there. Without this, deleting the emit line
# entirely would satisfy the guard above.
assert_ok "render_menu emits the frame via printf '%s' \"\$buf\"" \
    grep -q -F "printf '%s' \"\$buf\"" "$CDM_BIN"

# ---- terminal size comes from fd 3 (cdm:1132-1141) -------------------------
#
# Piped from curl, fd 0 IS the script, so `stty size` there fails outright — and
# it fails QUIETLY: the tput fallback answers from static terminfo with a
# plausible 24x80, so a regression here looks like a working program that ignores
# the bottom of everyone's window. There is no behavioural test for this that a
# non-pty test run could see, which is exactly why it is guarded statically.

assert_eq "" \
    "$(code_matching 'stty size' | grep -v '<&3')" \
    "every stty size reads fd 3 — fd 0 is the script itself under a curl pipe"

# ...and both callers still exist, so the guard above can't be satisfied by
# deleting them.
assert_ok "term_rows and term_cols both size the terminal from fd 3" \
    test "$(code_lines | grep -c 'stty size')" -ge 2

# ---- keypresses come from fd 3, never fd 0 (cdm:150) -----------------------
#
# Same root cause, louder failure: redirecting fd 0 would eat the rest of the
# program and break the pipe mid-run.

# Silent/keypress reads are interactive by definition — every one must use fd 3.
assert_eq "" \
    "$(code_matching 'read[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*s([[:space:]]|$)' | grep -v '<&3')" \
    "every keypress read (read -s) takes its input from fd 3"

# The obvious wrong fix, spelled explicitly.
assert_eq "" \
    "$(code_matching 'read.*<&0')" \
    "no read is redirected from fd 0"

# cdm's five interactive reads: wait_any_key, the "Proceed? (y/N)" prompt, the
# post-clean prompt, the menu key poll, and its escape-sequence follow-up. This
# count is what catches `<&3` being dropped from the ONE interactive read that
# carries no -s flag (the y/N prompt, cdm:1569) — the guard above cannot see it.
assert_ok "all five interactive reads still use <&3" \
    test "$(code_lines | grep -c 'read.*<&3')" -ge 5

# ---- release invariant -----------------------------------------------------
#
# The asset is piped straight into a user's shell. The shebang is what makes the
# saved-to-PATH copy in the README run under bash rather than the user's login
# shell — zsh is the macOS default and cdm is not zsh-compatible.

assert_eq '#!/bin/bash' "$(head -1 "$CDM_BIN")" "cdm's first line is exactly #!/bin/bash"

# ---- the floor itself ------------------------------------------------------
#
# Everything above is only worth enforcing if /bin/bash really is 3.2 — so prove
# it by behaviour rather than trusting the version string, and prove the specific
# claim that motivates this file: that bash 3.2 accepts `declare -A` and gets it
# wrong WITHOUT any nonzero exit for CI to notice.

BIN_BASH_MAJMIN=$(/bin/bash -c 'printf %s "${BASH_VERSION%.*}"' 2>/dev/null)

if [ "$BIN_BASH_MAJMIN" = "3.2" ]; then
    # Two distinct keys, one slot. Both subscripts evaluate arithmetically to 0,
    # so the second write clobbers the first and both read back "qux". On bash 4+
    # this is "bar,qux" — which is why the check is gated rather than
    # unconditional.
    assoc_probe=$(/bin/bash -c 'declare -A m 2>/dev/null
        m[foo]=bar; m[baz]=qux; printf "%s,%s" "${m[foo]}" "${m[baz]}"' 2>/dev/null)
    assoc_rc=$?

    assert_eq "qux,qux" "$assoc_probe" \
        "/bin/bash is 3.2: declare -A keys collapse to index 0 and silently alias"
    assert_eq "0" "$assoc_rc" \
        "declare -A EXITS 0 on 3.2 — no exit code, no bash -n error, only the guard above"

    assert_fail "/bin/bash 3.2 rejects \${v^^}" /bin/bash -c 'x=ab; : "${x^^}"'
else
    # Do not fail the suite here: a newer /bin/bash means the guards above are
    # unverified on this machine, not that cdm is broken. cdm still targets 3.2 —
    # that is fixed by macOS, not by this box.
    printf '  NOTE %s: /bin/bash is %s, not 3.2 — the bash-4 guards above still\n' \
        "$T_FILE" "${BIN_BASH_MAJMIN:-unknown}"
    printf '       apply (macOS ships 3.2.57), but this machine cannot demonstrate\n'
    printf '       the failures they prevent.\n'
    assert_ok "/bin/bash runs and reports a version" test -n "$BIN_BASH_MAJMIN"
fi

test_summary
