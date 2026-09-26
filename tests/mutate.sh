#!/bin/bash
# tests/mutate.sh — test the tests.
#
# A passing suite proves nothing on its own: an assertion that cannot fail is
# worse than no assertion, because it reads like coverage. This breaks cdm on
# purpose, one bug at a time, and asserts the suite NOTICES. A mutation that
# survives is a hole in the tests, reported here as a failure.
#
#   ./tests/mutate.sh
#
# Each mutation must clear three bars, all enforced below:
#   * it must actually change the file — a sed expression that silently stops
#     matching after a refactor would otherwise "pass" forever while testing
#     nothing, which is the exact failure mode this script exists to catch;
#   * the result must still pass `bash -n`, so we are testing the suite's grip
#     on BEHAVIOR rather than its ability to notice a syntax error;
#   * the named test file must then fail.

set -u

cd "$(dirname "$0")/.." || exit 1

MUT_TMP=$(mktemp -d "${TMPDIR:-/tmp}/cdm-mutate.XXXXXX") || exit 1
trap 'rm -rf "$MUT_TMP"' EXIT

total=0
survived=0

# check_mutation <description> <test-file> <sed-expression>
check_mutation() {
    local desc="$1" tfile="$2" expr="$3"
    local mut="$MUT_TMP/cdm"
    total=$((total + 1))

    if [ ! -f "tests/$tfile" ]; then
        printf 'SKIP  %-52s (no tests/%s)\n' "$desc" "$tfile"
        return 0
    fi

    sed "$expr" cdm > "$mut" || { printf 'ERROR %s (sed failed)\n' "$desc"; survived=$((survived + 1)); return 1; }

    if cmp -s cdm "$mut"; then
        printf 'ERROR %-52s (mutation matched nothing — stale pattern)\n' "$desc"
        survived=$((survived + 1))
        return 1
    fi

    if ! bash -n "$mut" 2>/dev/null; then
        printf 'ERROR %-52s (mutant does not parse; testing syntax, not behavior)\n' "$desc"
        survived=$((survived + 1))
        return 1
    fi

    if CDM_BIN="$mut" /bin/bash "tests/$tfile" >/dev/null 2>&1; then
        printf 'SURVIVED  %-48s <- tests/%s did not catch this\n' "$desc" "$tfile"
        survived=$((survived + 1))
        return 1
    fi

    printf 'caught    %-48s (tests/%s)\n' "$desc" "$tfile"
    return 0
}

# ---- is_safe_target: the gate every deletion passes through -----------------

check_mutation 'protected set: ~/Documents no longer matches' test_safe_target.sh \
    's|"\$HOME"/Documents\|"\$HOME"/Documents/\*|"$HOME"/DocumentsZZ\|"$HOME"/DocumentsZZ/*|'

check_mutation 'protected set: ~/.ssh no longer matches' test_safe_target.sh \
    's|"\$HOME"/\.ssh\|"\$HOME"/\.ssh/\*|"$HOME"/.sshZZ\|"$HOME"/.sshZZ/*|'

check_mutation '".." traversal guard dropped' test_safe_target.sh \
    's|case "\$p" in \*\.\.\*) return 1 ;; esac|case "$p" in *ZZZNOMATCHZZZ*) return 1 ;; esac|'

check_mutation 'physical containment always succeeds' test_safe_target.sh \
    's|case "\$rp/" in "\$HOME_P/"\|"\$HOME_P"/\*) return 0 ;; \*) return 1 ;; esac|return 0|'

check_mutation 'physical containment checks $HOME not $HOME_P' test_safe_target.sh \
    's|case "\$rp/" in "\$HOME_P/"\|"\$HOME_P"/\*) return 0 ;; \*) return 1 ;; esac|case "$rp/" in "$HOME/"\|"$HOME"/*) return 0 ;; *) return 1 ;; esac|'

check_mutation 'lexical containment under $HOME dropped' test_safe_target.sh \
    's|case "\$p" in "\$HOME"/\*) : ;; \*) return 1 ;; esac|:|'

check_mutation 'existence check dropped' test_safe_target.sh \
    's|\[ -e "\$p" \] \|\| return 1|:|'

# Two mutations are deliberately NOT listed here, because is_safe_target's early
# guards are defense-in-depth and the lexical + physical pair already subsumes
# them — no input distinguishes the mutant, so no test could ever catch one:
#
#   * dropping the `"$HOME"|"$HOME/"|"$HOME_P"|"$HOME_P/"` branch. All four are
#     still refused: none of them matches the lexical "$HOME"/* pattern (which
#     needs a trailing component), and "$HOME/" dirnames up to the home's parent
#     and fails physical containment.
#   * accepting relative paths. A relative path cannot begin with the absolute
#     "$HOME/", so the lexical check refuses it regardless of the cwd.
#
# Both were verified as equivalent mutants against the real script rather than
# assumed. Listing them would mean permanently reporting a hole the tests are
# not able to close, which trains the reader to ignore this output.

# ---- small helpers ---------------------------------------------------------

check_mutation 'human_kb MB threshold 1024 -> 1000' test_helpers.sh \
    's|elif \[ "\$kb" -ge 1024 \]|elif [ "$kb" -ge 1000 ]|'

check_mutation 'human_kb GB threshold off by one' test_helpers.sh \
    's|\[ "\$kb" -ge 1048576 \]|[ "$kb" -gt 1048576 ]|'

# The comma-decimal bug, which shipped: awk's %f writes the separator LC_NUMERIC
# names, so unpinned this renders "1,00 GB" under any European locale. It hid
# because the suite only ever ran under the developer's locale — the same reason
# the is_ascii range bug below hid — so test_helpers.sh now pins its own.
check_mutation 'human_kb GB loses its LC_ALL=C (comma separator)' test_helpers.sh \
    's|-ge 1048576 \]; then LC_ALL=C awk|-ge 1048576 ]; then awk|'

# Weakening the pin to LC_NUMERIC=C, which is the fix a reader is most likely to
# reach for and is WRONG: LC_ALL outranks LC_NUMERIC in the process that reads
# it, so this still prints a comma for anyone exporting LC_ALL=de_DE.UTF-8 —
# which is exactly what in_locale sets. (docs/DESIGN.md#numeric-format)
check_mutation 'human_kb GB pins LC_NUMERIC, which LC_ALL outranks' test_helpers.sh \
    's|-ge 1048576 \]; then LC_ALL=C awk|-ge 1048576 ]; then LC_NUMERIC=C awk|'

# The MB branch's LC_ALL=C is deliberately NOT mutated here: it is an equivalent
# mutant. That branch formats with %.0f, which keeps no fraction and so emits no
# separator at all under any locale — no input distinguishes the mutant, and no
# assertion could catch it. It is pinned in cdm anyway because it sits one edit
# ('%.0f' -> '%.1f') away from being the same bug, and the MB rows in
# test_helpers.sh are what would notice that edit. Verified to survive against
# the real script rather than assumed.

check_mutation 'human_to_kb: kB treated as binary' test_helpers.sh \
    's|kB\|KB\|kb) mult=1000 ;;|kB\|KB\|kb) mult=1024 ;;|'

check_mutation 'engine_ok accepts anything' test_helpers.sh \
    's|case "\$1" in docker\|podman\|nerdctl) return 0 ;; \*) return 1 ;; esac|return 0|'

# ---- disk status (docs/DESIGN.md#disk-status) -------------------------------
#
# Two families. The df PARSE is mutated against a fake df the test controls, so
# the columns, the record and the derivation are pinned exactly; the -k is
# mutated against the real filesystem, which is the one thing a fake df cannot
# see — every wrong unit still returns a plausible integer.

check_mutation 'df asked for MiB instead of KiB' test_disk_status.sh \
    's|\$(df -Pk "\$HOME"|$(df -Pm "$HOME"|'

check_mutation 'df parse reads the header row' test_disk_status.sh \
    "s|awk 'NR==2 {print \$2, \$4}'|awk 'NR==1 {print \$2, \$4}'|"

check_mutation 'free read from df Used instead of Available' test_disk_status.sh \
    "s|awk 'NR==2 {print \$2, \$4}'|awk 'NR==2 {print \$2, \$3}'|"

check_mutation 'used no longer derived as total - available' test_disk_status.sh \
    's|DISK_USED_KB=\$((total - avail))|DISK_USED_KB=$((total + avail))|'

check_mutation 'available not clamped to capacity (used goes negative)' test_disk_status.sh \
    's|\[ "\$avail" -gt "\$total" \] && avail="\$total"|:|'

check_mutation 'a zero-capacity filesystem is accepted' test_disk_status.sh \
    's|\[ "\$total" -gt 0 \] \|\| return 1|:|'

# The fixture that catches this feeds a field bash arithmetic WOULD accept
# (0x10 -> 16) rather than one that makes it fatal: a dash aborts the arithmetic
# outright, and an abort is indistinguishable from the refusal the guard exists
# to produce — it even unwinds past the assertion that was watching for it.
check_mutation 'a non-numeric "available" is accepted' test_disk_status.sh \
    's|    case "\$avail" in ..\|\*\[!0-9\]\*) return 1 ;; esac|    :|'

# Its twin — dropping the same guard on `total` — is deliberately absent: it is
# an equivalent mutant, because `[ "$total" -gt 0 ] || return 1` on the next
# line is itself a numeric gate. bash's `[` refuses a non-integer with a status
# of 2 (it does not read 0x10 as 16 the way $(( )) does), so every value the
# case would have caught is refused one line later anyway. `avail` has no such
# backstop — its only comparison is a clamp whose failure is not an error path —
# which is why that half IS mutated. Verified to survive rather than assumed;
# the guard stays in cdm because the two fields should visibly answer to the
# same rule, not because behavior depends on it.

check_mutation 'disk_used_pct truncates instead of rounding' test_disk_status.sh \
    's|(DISK_USED_KB \* 100 + DISK_TOTAL_KB / 2) / DISK_TOTAL_KB|(DISK_USED_KB * 100) / DISK_TOTAL_KB|'

check_mutation 'disk_line renders a disk that was never measured' test_disk_status.sh \
    's|    \[ "\$DISK_TOTAL_KB" -gt 0 \] \|\| return 1|    :|'

# The one that would have shipped silently: disk_line is called from inside
# $(...), where a refresh sets the globals in a subshell and loses them — the
# same trap compute_sizes_write documents. The menu row would then show a disk
# it never measured.
check_mutation 'disk_line refreshes instead of formatting' test_disk_status.sh \
    's|^disk_line() {|disk_line() { disk_stats;|'

check_mutation 'total_kb counts only the selected rows' test_disk_status.sh \
    's|^total_kb()       { local i t=0; for i in \$(cat_indices); do t=|total_kb()       { local i t=0; for i in $(cat_indices); do [ "${CAT_SEL[$i]}" = "1" ] \&\& t=|'

# ---- the menu's status row (docs/DESIGN.md#status-line) ---------------------
#
# Every one of these produces a row WIDER than the window it was built for,
# which is not a cosmetic bug: the frame is a fixed height, so an extra physical
# line scrolls the whole menu on every repaint.

check_mutation 'status row never sheds the disk figures' test_disk_status.sh \
    's|if \[ "\$tier" -le 1 \] && \[ -n "\$disk" \]; then|if [ -n "$disk" ]; then|'

check_mutation 'status row never degrades at all' test_disk_status.sh \
    's|\[ "\$_DW" -le "\$cols" \] && break|break|'

check_mutation 'status row plain shadow loses the max (mis-measured)' test_disk_status.sh \
    's|_SS="\${_SS}\${DIM} of \${tot_h}\${NC}"; _SP="\${_SP} of \${tot_h}"|_SS="${_SS}${DIM} of ${tot_h}${NC}"|'

check_mutation 'status row plain shadow loses the disk (mis-measured)' test_disk_status.sh \
    's|_SS="\${_SS}   \${DIM}Disk \${disk}\${NC}"; _SP="\${_SP}   Disk \${disk}"|_SS="${_SS}   ${DIM}Disk ${disk}${NC}"|'

# One is deliberately absent: measuring _SS instead of _SP (`dwidth "$_SP"` ->
# `dwidth "$_SS"`). It is the exact defect _P/_SP exist to prevent — escapes
# carry no columns, so the styled string measures far too wide — but the suite
# runs with stdout redirected, where cdm's own `[ -t 1 ]` check leaves every
# colour empty and the two strings are byte-identical. No assertion in a piped
# test run can distinguish it. The lockstep rows above cover the reachable half
# of that risk; verified to survive rather than assumed.

# ---- the post-clean prompt (docs/DESIGN.md#after-clean-menu) ----------------

# Addressed to the function: `*) return 1 ;;` is a shape that appears in other
# case statements, and a global rewrite would mutate one of those instead.
check_mutation 'post-clean prompt defaults to rescan, not quit' test_after_clean_menu.sh \
    '/^after_clean_menu()/,/^}/ s|            \*)   return 1 ;;|            *)   return 0 ;;|'

check_mutation 'post-clean prompt ignores an uppercase R' test_after_clean_menu.sh \
    's|            r\|R) return 0 ;;|            r) return 0 ;;|'

check_mutation 'donating quits instead of re-asking' test_after_clean_menu.sh \
    's|            b\|B) open_donate ;;|            b\|B) open_donate; return 1 ;;|'

# The key choice itself. `d` is the main menu's details key, and a prompt that
# quietly takes it back gives one letter two meanings across the tool.
check_mutation 'the donate key moves back onto d (collides with details)' test_after_clean_menu.sh \
    's|            b\|B) open_donate ;;|            d\|D) open_donate ;;|'

check_mutation 'the donate key opens something other than DONATE_URL' test_after_clean_menu.sh \
    's|if open "\$DONATE_URL" >/dev/null 2>&1; then|if open "$LOG_FILE" >/dev/null 2>\&1; then|'

check_mutation 'a failed open swallows the URL' test_after_clean_menu.sh \
    's|        printf .%b\\n. "  \${CYAN}\${DONATE_URL}\${NC}"|        :|'

check_mutation 'expand_tilde ignores bare ~' test_helpers.sh \
    's|"~") echo "\$HOME" ;;|"~") echo "~" ;;|'

check_mutation 'is_nonempty misses dotfile-only dirs' test_helpers.sh \
    's|for __e in "\$1"/\* "\$1"/\.\[!\.\]\*; do|for __e in "$1"/*; do|'

# ---- display width ---------------------------------------------------------

check_mutation 'wide-char lead byte boundary 227 -> 300' test_text_width.sh \
    's|if \[ "\$v" -ge 227 \]; then _CW=2|if [ "$v" -ge 300 ]; then _CW=2|'

check_mutation 'every char measured as one column' test_text_width.sh \
    's|if \[ "\$v" -ge 227 \]; then _CW=2; else _CW=1; fi|_CW=1|'

check_mutation 'clip_plain off-by-one leaves no room for ellipsis' test_text_width.sh \
    's|\[ \$((w + _CW)) -gt \$((max - 1)) \] && break|[ $((w + _CW)) -gt $max ] \&\& break|'

check_mutation 'shorten_left clips from the right instead' test_text_width.sh \
    's|else _CLIP="…\${s:\$((\${#s} - max + 1))}"; fi|else _CLIP="…${s:0:$((max - 1))}"; fi|'

# The ${s: -0} defect, which the dead fast path below masked for the life of the
# tool: -0 is not negative, so bash reads it as offset 0 and returns the whole
# string. Only reachable — and so only catchable — now that the guard works.
check_mutation 'shorten_left fast path regains the ${s: -0} defect' test_text_width.sh \
    's|else _CLIP="…\${s:\$((\${#s} - max + 1))}"; fi|else _CLIP="…${s: -$((max - 1))}"; fi|'

# The guard is a character CLASS, never a bracket range. The first of these is
# the bug that shipped: a range is resolved by LC_COLLATE, cdm pins only
# LC_CTYPE, and under any locale but C/POSIX the range ' ' to '~' excludes every
# letter, so the guard answered "not ASCII" for "abc" and all three fast paths
# were dead code. It changed no output, only speed, which is why nothing caught it —
# test_text_width.sh catches it now by asserting is_ascii under a locale it pins
# itself, rather than the one the developer happens to be running.
check_mutation 'is_ascii guard reverts to a collation-dependent range' test_text_width.sh \
    's|\*\[!\[:ascii:\]\]\*) return 1 ;;|*[!\\ -~]*) return 1 ;;|'

# Mutating the ACTION, not the pattern. The `*ZZZNOMATCHZZZ*` idiom used above
# only never-matches as a literal substring: inside brackets, `[!ZZZNOMATCHZZZ]`
# is a negated SET, so shrinking it makes the guard match MORE and quietly gives
# you the mutation below a second time. This direction is the one that corrupts
# output rather than costing speed — dwidth then measures 中文字 at 3 columns.
check_mutation 'is_ascii calls everything ASCII' test_text_width.sh \
    's|\*\[!\[:ascii:\]\]\*) return 1 ;;|*[![:ascii:]]*) return 0 ;;|'

check_mutation 'is_ascii calls nothing ASCII (fast paths dead)' test_text_width.sh \
    's|^        \*) return 0 ;;$|        *) return 1 ;;|'

# Three more are deliberately absent: replacing `if is_ascii "$s"` with `if false`
# in dwidth, clip_plain or shorten_left. Each makes that fast path dead code
# again — the exact bug fixed here — but the fast and slow paths agree on every
# output by construction, so no INPUT distinguishes the mutant; it costs speed,
# not correctness. Catching one would mean stubbing is_ascii and asserting it was
# called, i.e. pinning an implementation detail rather than behavior. All three
# were verified to survive rather than assumed. 'is_ascii calls nothing ASCII'
# above covers the real risk — a guard that answers "not ASCII" for "abc" — at
# the guard itself, which is where the bug actually was.

# ---- the orphan shape filter -----------------------------------------------
#
# looks_like_bundle_id gates every orphaned-app-data lookup, so its accepted set
# IS the deletion-candidate set. Same class of bug as is_ascii above, one level
# up in consequence: `*[!A-Za-z0-9._-]*` is a range, resolved by LC_COLLATE,
# which cdm does not pin — so the orphan list depended on the user's LANG.

check_mutation 'looks_like_bundle_id drops its ASCII restriction' test_bundle_id.sh \
    's|    is_ascii "\$1" \|\| return 1|    :|'

check_mutation 'looks_like_bundle_id accepts any name shape' test_bundle_id.sh \
    's|\*\[!\[:alnum:\]\._-\]\*) return 1 ;;|*[![:alnum:]._-]*) return 0 ;;|'

check_mutation 'looks_like_bundle_id stops requiring reverse-DNS' test_bundle_id.sh \
    's|case "\$1" in \*\.\*\.\*) : ;; \*) return 1 ;; esac|case "$1" in *.*) : ;; *) return 1 ;; esac|'

# The first of those is the interesting one, and it is the NAIVE FIX rather than
# the original bug: dropping is_ascii leaves `*[![:alnum:]._-]*`, which is a
# class, so it is LC_CTYPE-based and locale-consistent — and consistently WIDER
# than the bug it replaces, because cdm's pin forces a UTF-8 ctype, where
# [[:alnum:]] means "any alphanumeric in Unicode". It newly offers a folder named
# 私の.大切な.データ for deletion. test_bundle_id.sh catches it on the CJK cases.
#
# One is deliberately absent: swapping the class back to `*[!A-Za-z0-9._-]*`.
# With is_ascii in front, only ASCII reaches that case, and over ASCII the range
# and the class accept the same characters under every collation — an EQUIVALENT
# mutant, verified to survive rather than assumed. That is not a hole: is_ascii
# is the half doing the locale-proofing, and removing it is the mutation above.
# see docs/DESIGN.md#bundle-id-shape

# ---- the git-ignored proof (docs/DESIGN.md#ignored-proof) -------------------
#
# The bug that shipped: a name-matched dir was offered for permanent `rm` on the
# strength of its BASENAME alone, so a tracked build/ of release scripts, a
# committed dist/ or a vendored Pods/ all looked like junk. Every mutation here
# puts some version of that back.

check_mutation 'name match alone is enough (proof not consulted)' test_ignored_proof.sh \
    's|                      if (d in I) { print; next }|                      if (1) { print; next }|'

check_mutation 'the proof accepts nothing (all project junk lost)' test_ignored_proof.sh \
    's|                      if (d in I) { print; next }|                      if (0) { print; next }|'

# Only exact hits count. `git ls-files --directory` collapses a wholly ignored
# tree to one entry, so a dist/ inside one is never named — this drops it.
check_mutation 'proof stops walking to the collapsed ancestor' test_ignored_proof.sh \
    's|                      sub(/\\/\[^\\/\]\*\$/, "", d)|                      break|'

# The walk must end AT the candidate's own repo root. Past it, an outer repo
# that ignores a nested checkout authorizes deleting what that checkout tracks.
check_mutation 'proof walks past the repo root into the enclosing repo' test_ignored_proof.sh \
    's|while (d != \$1 && d != "" && d != "/")|while (d != "" \&\& d != "/")|'

# The proof is read from a listing keyed by repo; feeding the walk the repo
# roots instead of the ignored paths makes it match nothing real.
check_mutation 'proof indexes the repo column instead of the ignored path' test_ignored_proof.sh \
    's|if (split(l, a, FS) >= 2) I\[a\[2\]\] = 1|if (split(l, a, FS) >= 2) I[a[1]] = 1|'

# The git pass must run for candidate-holding repos even when the git-ignored
# category is off — that is the only source of proof in a -p scan without it.
check_mutation 'the git pass only runs when the git-ignored category is on' test_ignored_proof.sh \
    "s|        awk -F \"\$us\" 'NF { print \$1 }' \"\$cands\"|        :|"

# ---- category model --------------------------------------------------------

check_mutation 'prune_zero drops CAT_METHOD from the compaction' test_categories.sh \
    's|CAT_METHOD\[\$w\]="\${CAT_METHOD\[\$r\]}"|:|'

check_mutation 'prune_zero drops CAT_SUMMARY from the compaction' test_categories.sh \
    's|CAT_SUMMARY\[\$w\]="\${CAT_SUMMARY\[\$r\]}"|:|'

check_mutation 'sort_by_size forgets to carry CAT_NAME' test_categories.sh \
    's|CAT_NAME\[\$i\]="\${NAME\[\$i\]}"|:|'

check_mutation 'sort_by_size forgets to carry CAT_PATHS' test_categories.sh \
    's|CAT_PATHS\[\$i\]="\${PATHS\[\$i\]}"|:|'

# ---- delete path -----------------------------------------------------------

check_mutation 'delete_path skips the safety gate' test_delete_path.sh \
    's|if ! is_safe_target "\$p"; then|if false; then|'

check_mutation 'move_to_trash clobbers an existing name' test_delete_path.sh \
    's|if \[ -e "\$dest" \]; then|if false; then|'

# ---- log rotation ----------------------------------------------------------

check_mutation 'rotate_log never fires (cap ignored)' test_log_rotation.sh \
    's|\[ "\$sz" -le "\$LOG_MAX_BYTES" \] && return 0|return 0|'

check_mutation 'rotate_log keeps the OLDEST entries' test_log_rotation.sh \
    's|tail -c "\$LOG_KEEP_BYTES" "\$LOG_FILE" 2>/dev/null \| sed .1d.|head -c "$LOG_KEEP_BYTES" "$LOG_FILE" 2>/dev/null|'

check_mutation 'rotate_log leaves the mid-line partial record' test_log_rotation.sh \
    's|tail -c "\$LOG_KEEP_BYTES" "\$LOG_FILE" 2>/dev/null \| sed .1d.|tail -c "$LOG_KEEP_BYTES" "$LOG_FILE" 2>/dev/null|'

check_mutation 'rotate_log truncates a small log too' test_log_rotation.sh \
    's|\[ "\$sz" -le "\$LOG_MAX_BYTES" \] && return 0|:|'

# Both halves are needed to make the leak observable: swapping mv for cp alone is
# an equivalent mutant, because the unconditional `rm -f "$tmp"` on the next line
# tidies up regardless. Mutating only the mv would report a permanent false hole.
check_mutation 'rotate_log leaves its temp file behind' test_log_rotation.sh \
    's|mv "\$tmp" "\$LOG_FILE" 2>/dev/null|cp "$tmp" "$LOG_FILE" 2>/dev/null|; s|^    rm -f "\$tmp" 2>/dev/null$|    :|'

# ---- stale scan-dir sweep --------------------------------------------------
#
# This rm does not pass is_safe_target, so the glob IS the safety boundary.
# These mutations widen it on purpose; the tests must refuse every one.

check_mutation 'sweep glob widened to cdm.*' test_scan_dir_sweep.sh \
    's|for d in "\${TMPDIR:-/tmp}"/cdm\.??????; do|for d in "${TMPDIR:-/tmp}"/cdm.*; do|'

check_mutation 'sweep glob widened to everything in TMPDIR' test_scan_dir_sweep.sh \
    's|for d in "\${TMPDIR:-/tmp}"/cdm\.??????; do|for d in "${TMPDIR:-/tmp}"/*; do|'

check_mutation 'sweep ignores the mtime floor' test_scan_dir_sweep.sh \
    's|\[ -n "\$(find "\$d" -maxdepth 0 -mmin +60 2>/dev/null)" \] \|\| continue|:|'

check_mutation "sweep eats this run's own SCAN_DIR" test_scan_dir_sweep.sh \
    's|\[ "\$d" = "\${SCAN_DIR:-}" \] && continue|:|'

check_mutation 'sweep no longer checks it is a directory' test_scan_dir_sweep.sh \
    's|\[ -d "\$d" \] \|\| continue|[ -e "$d" ] \|\| continue|'

# ---- static / portability guards -------------------------------------------

check_mutation 'a bash-4 associative array creeps in' test_portability.sh \
    's|^human_kb() {|declare -A _mut_map\nhuman_kb() {|'

check_mutation 'the frame is printf-ed as a format string' test_portability.sh \
    "s|printf '%s' \"\$buf\"|printf \"\$buf\"|"

# ---- sort -u collation ------------------------------------------------------
#
# One per site: drop the LC_ALL=C pin and leave -u comparing by the user's
# collation. Only the first is caught by behaviour (flush_project_category takes
# its names as an argument); the other three need a real filesystem or
# lsregister to reach, so the static guard in test_sort_locale.sh is what holds
# them. That is a weaker grip than a behavioural assertion and worth naming: it
# proves the pin is written, not that it works. The first mutation is what
# proves the pin does anything at all.

check_mutation 'project summary sort -u unpinned' test_sort_locale.sh \
    's@| LC_ALL=C sort -u | awk@| sort -u | awk@'

check_mutation 'find -name list sort -u unpinned' test_sort_locale.sh \
    's@| LC_ALL=C sort -u)@| sort -u)@'

check_mutation 'installed bundle-id sort -u unpinned' test_sort_locale.sh \
    's@| LC_ALL=C sort -u > "\$INSTALLED"@| sort -u > "$INSTALLED"@'

check_mutation 'orphan bid sort -u unpinned' test_sort_locale.sh \
    's@cut -f1 "\$raw" | LC_ALL=C sort -u@cut -f1 "$raw" | sort -u@'

# ---- group roots (docs/DESIGN.md#group-roots) -------------------------------
#
# Three behaviour-bearing steps, each mutated once: the group roots never reach
# the awk matcher (the load), a repo's key is never remapped onto its enclosing
# root (the group never forms), and the grouped row never learns how many repos
# it stands for (the count prefix). All three surface as a wrong row set or a
# summary that lies about being one repo.

check_mutation 'group roots never loaded into the matcher (no group forms)' test_project_grouping.sh \
    's@G\[++ng\] = l@G[ng] = l@'

check_mutation 'item key never remapped onto its group root (no group forms)' test_project_grouping.sh \
    's@{ \$1 = G\[i\]; break }@{ break }@'

check_mutation 'repo count tallies items, not distinct repos (dedup dropped)' test_project_grouping.sh \
    's@NF && !seen\[\$0\]++ { c++ }@NF { c++ }@'

# ---- the .env* exception (docs/DESIGN.md#env-file-exception) -----------------
#
# Neuter the basename guard so git-ignored .env* files flow through to the delete
# set. The test's positive half (secret.conf still offered) means an empty scan
# can't hide the negative half, so this must surface as .env* appearing.

check_mutation '.env* guard neutered (secrets offered for deletion)' test_env_exception.sh \
    's@case "\$bn" in \.env\*) continue ;; esac@case "$bn" in .envZNOMATCH*) continue ;; esac@'

# ---- the running-app check (docs/DESIGN.md#running-app-check) ---------------
#
# The two CAT_PROCS-alignment mutations are the reason this section exists. A
# parallel array that is not copied by prune_zero/sort_by_size does not fail
# loudly, it just slides one row out of step — cdm would warn about Chrome
# because Slack is running, and the menu would look completely normal.

check_mutation 'sort_by_size drops CAT_PROCS (procs slide off their row)' test_running_apps.sh \
    's|        PROCS\[\$j\]="\${CAT_PROCS\[\$i\]}"||'

check_mutation 'sort_by_size never restores CAT_PROCS' test_running_apps.sh \
    's|        CAT_PROCS\[\$i\]="\${PROCS\[\$i\]}"||'

check_mutation 'prune_zero drops CAT_PROCS (procs slide off their row)' test_running_apps.sh \
    's|                CAT_PROCS\[\$w\]="\${CAT_PROCS\[\$r\]}"||'

check_mutation 'JXA stops emitting PROC records (rules procs never load)' test_running_apps.sh \
    "s@(c.procs   || \[\]).forEach(function(p){ out.push(tab('PROC', p)); });@@"

check_mutation 'parser ignores PROC records' test_running_apps.sh \
    's|            PROC) cprocs="\${cprocs:+\$cprocs|            ZZPROC) cprocs="${cprocs:+$cprocs|'

check_mutation 'cprocs not reset per category (procs leak to the next rule)' test_running_apps.sh \
    's|have=1; cpaths=""; cdirs=""; cengines=""; cprocs="" ;;|have=1; cpaths=""; cdirs=""; cengines="" ;;|'

check_mutation 'register_paths drops procs on the way to add_category' test_running_apps.sh \
    's|"\$default" "\$found" "" "\$procs"|"$default" "$found" ""|'

check_mutation 'de-dup dropped (one app named once per category)' test_running_apps.sh \
    's@            seen="${seen}|$name|"@@'

# Addressed to the function: the same CAT_SEL guard line appears at four sites,
# and a global rewrite would mutate run_cleanup's deletion loop too — a much
# louder bug than the one under test here.
check_mutation 'unselected categories are probed too' test_running_apps.sh \
    '/^running_selected_apps()/,/^}/ s@\[ "${CAT_SEL\[$i\]}" = "1" \] || continue@[ "${CAT_SEL[$i]}" != "ZZ" ] || continue@'

check_mutation 'pgrep loses -x (Google Chrome Helper would match)' test_running_apps.sh \
    's|pgrep -xq "\$name"|pgrep -q "$name"|'

echo
printf 'mutations: %d, survived (holes in the tests): %d\n' "$total" "$survived"
if [ "$survived" -gt 0 ]; then
    echo 'FAIL — every surviving mutation is a bug the suite would not catch.'
    exit 1
fi
echo 'ok — the suite catches every mutation.'
