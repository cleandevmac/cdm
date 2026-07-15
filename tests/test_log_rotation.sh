#!/bin/bash
# rotate_log (cdm) — keeps ~/.cleandevmac/clean.log from growing forever.
#
# run_cleanup appends a receipt per clean via `tee -a` and nothing ever trimmed
# it, so the log was unbounded. The properties worth pinning are that it caps,
# that it keeps the NEWEST entries (the ones anyone actually reads), and that it
# leaves a small log alone — a rotation that fires early would throw away
# history for no reason.

. "$(dirname "$0")/lib.sh"

# lib.sh sandboxes $HOME, so LOG_DIR/LOG_FILE already point inside the sandbox.
assert_ok "log dir is sandboxed" test "$LOG_DIR" = "$HOME/.cleandevmac"

# ---- a small log is left alone ---------------------------------------------

mkdir -p "$LOG_DIR"
printf 'first entry\nsecond entry\n' > "$LOG_FILE"
before=$(stat -f%z "$LOG_FILE")
rotate_log
assert_eq "$before" "$(stat -f%z "$LOG_FILE")" "a small log is not touched"
assert_eq "first entry" "$(head -1 "$LOG_FILE")" "a small log keeps its oldest entry"

# ---- a missing log is not an error -----------------------------------------

rm -f "$LOG_FILE"
assert_ok "missing log rotates cleanly" rotate_log
assert_ok "missing log is not created by rotation" test ! -f "$LOG_FILE"

# ---- an oversized log is capped --------------------------------------------

# Each line is tagged with its ordinal so we can prove WHICH end survived.
# Sized past LOG_MAX_BYTES (1 MiB) with room to spare.
: > "$LOG_FILE"
i=0
while [ "$i" -lt 30000 ]; do
    printf 'line %d: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' "$i"
    i=$((i + 1))
done > "$LOG_FILE"

big=$(stat -f%z "$LOG_FILE")
assert_ok "fixture really is over the cap" test "$big" -gt "$LOG_MAX_BYTES"

rotate_log
now=$(stat -f%z "$LOG_FILE")

assert_ok "oversized log is shrunk" test "$now" -lt "$big"
assert_ok "rotated log is under the cap" test "$now" -le "$LOG_MAX_BYTES"

# The newest entries are what survive: the final line must still be the last one
# written. A rotation that kept the HEAD instead would pass a naive size check
# and silently discard the only entries anyone ever looks at.
assert_eq "line 29999: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
    "$(tail -1 "$LOG_FILE")" "the newest entry survives rotation"

assert_ok "the oldest entry is gone" \
    test -z "$(grep -c '^line 0:' "$LOG_FILE" | grep '^[1-9]')"

# `tail -c` slices at a byte offset, so it lands mid-line; rotate_log drops that
# partial record. Every surviving log line must therefore be whole — assert no
# line is a fragment of the known format rather than trusting the sed '1d'.
assert_eq "0" "$(sed -n '/^=/d; /^Truncated /d; /^line [0-9]*: a*$/d; p' "$LOG_FILE" | grep -c .)" \
    "no partial line survives the byte-offset slice"

assert_ok "a truncation marker is left behind" \
    grep -q '^Truncated ' "$LOG_FILE"

# ---- rotation is idempotent / stable ---------------------------------------

again_before=$(stat -f%z "$LOG_FILE")
rotate_log
assert_eq "$again_before" "$(stat -f%z "$LOG_FILE")" \
    "rotating an already-rotated log is a no-op"

# ---- no scratch files left behind ------------------------------------------

assert_eq "" "$(ls "$LOG_DIR"/.clean.log.* 2>/dev/null)" \
    "rotation leaves no temp file behind"

test_summary
