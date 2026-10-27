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
    's|case "\$p" in "\$HOME"/\*) : ;; \*) in_user_folder "\$p"; return ;; esac|:|'

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

# ---- this user's own temp folders (docs/DESIGN.md#user-folder) ---------------
#
# is_safe_target's second branch, and the tokens rules reach it with. The folder
# is sandboxed outside $HOME, so an acceptance can only come from that branch.

check_mutation 'per-user branch never consulted' test_user_folder.sh \
    's@\*) in_user_folder "\$p"; return ;; esac@*) return 1 ;; esac@'

check_mutation 'user folder: a folder below it accepted' test_user_folder.sh \
    's@    case "\${rest#??/}" in \*/\*) return 1 ;; esac@    :@'

check_mutation 'user folder: ownership unchecked' test_user_folder.sh \
    's@ && \[ -O "\$1" \]$@@'

check_mutation 'in_user_folder: physical containment dropped' test_user_folder.sh \
    's@    case "\$rp/" in "\$USER_FOLDER"/\[CTX\]/\*) return 0 ;; \*) return 1 ;; esac@    return 0@'

check_mutation 'in_user_folder: lexical containment dropped' test_user_folder.sh \
    's@    case "\$p" in "\$USER_FOLDER"/\[CTX\]/?\*) : ;; \*) return 1 ;; esac@    :@'

check_mutation 'in_user_folder: any folder, not only C, T and X' test_user_folder.sh \
    '/^in_user_folder()/,/^}/ s@\[CTX\]@*@g'

check_mutation 'in_user_folder: a "." segment accepted' test_user_folder.sh \
    's@    case "\$p" in \*/\.|\*/\./\*) return 1 ;; esac@    :@'

check_mutation 'tokens expand with no user folder' test_user_folder.sh \
    's@    \[ -n "\$USER_FOLDER" \] || { echo "\$1"; return; }@    :@'

check_mutation '@temp/ points at the cache folder' test_user_folder.sh \
    's|        @temp/\*) root=T ;;|        @temp/*) root=C ;;|'

# Three guards are deliberately NOT listed, for the reason given above — no
# input on a stock Mac distinguishes the mutant:
#
#   * user_folder_ok's first shape case and its `! -L`: the input is `pwd -P`
#     output, which is never a symlink, and the depth check plus ownership refuse
#     every other shape a real Mac has (/private/var/folders/<xx> is root's).
#   * in_user_folder's empty-USER_FOLDER guard: the patterns then only match
#     /C, /T and /X at the filesystem root, which do not exist, and is_safe_target
#     checks existence first.

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
    's|"~") echo "\$HOME"; return ;;|"~") echo "~"; return ;;|'

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
    's|cengines=""; cprocs=""; cimages=""; ccands|cengines=""; cimages=""; ccands|'

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

# ---- android-images: never offer an image an AVD still boots from ----------

check_mutation 'register_paths ignores its skip list' test_android_images.sh \
    's|            \[ -n "\$skip" \] \&\& ends_with_any "\$m" "\$skip" \&\& { IFS=; continue; }||'

check_mutation 'android-images passes no AVD refs' test_android_images.sh \
    's|"\$cprocs" "\$(avd_image_refs)" ;;|"$cprocs" ;;|'

check_mutation 'android-images kind unrecognised (falls to paths)' test_android_images.sh \
    's|^        android-images)$|        zz-android-images)|'

check_mutation 'parser ignores IMG records' test_android_images.sh \
    's|            IMG) cimages=|            ZZIMG) cimages=|'

check_mutation 'JXA stops emitting IMG records' test_android_images.sh \
    "s@(c.images  || \[\]).forEach(function(p){ out.push(tab('IMG', p)); });@@"

check_mutation 'image.sysdir trailing slash kept (ref never matches)' test_android_images.sh \
    's@\*" "|\*/) v="\${v%?}" ;;@*" ") v="${v%?}" ;;@'

check_mutation 'AVD <name>.ini path= ignored (AVD outside avd home)' test_android_images.sh \
    's|path=\*) line="\${line#path=}"|zzpath=*) line="${line#path=}"|'

check_mutation 'ANDROID_AVD_HOME ignored' test_android_images.sh \
    's|for home in "\${ANDROID_AVD_HOME:-}" |for home in |'

check_mutation 'ends_with_any drops the / boundary' test_android_images.sh \
    's@case "\$1" in "\$r"|\*/"\$r") return 0@case "$1" in *"$r") return 0@'

# ---- buildx builders' caches (docs/DESIGN.md#buildx-builders) ---------------
#
# The fake docker answers only the exact --format strings, so a template that
# drifts back to a field buildx lacks, or to the \n docker rewrites, is caught as
# surely as a dropped guard. The order rows are the ones that matter most: run
# out of order, the clean either deletes a stopped builder's container before it
# can be started, or leaves a builder running that the user had stopped.

check_mutation 'buildx ls asks for .Driver, which its template lacks' test_buildx.sh \
    's@{{.DriverEndpoint}}@{{.Driver}}@'

check_mutation 'volume rows end in {{"\n"}}, which docker breaks' test_buildx.sh \
    's@{{.Size}}{{println}}{{end}}@{{.Size}}{{"\\n"}}{{end}}@'

check_mutation 'docker-driver builders counted' test_buildx.sh \
    's@        \[ "\$drv" = "docker-container" \] || continue@        :@'

check_mutation 'inactive nodes (no container) counted' test_buildx.sh \
    's@case "\$f3" in running|stopped)@case "$f3" in running|stopped|inactive)@'

check_mutation 'node names reach docker unchecked' test_buildx.sh \
    's@        buildx_name_ok "\$name" || continue@        :@'

check_mutation 'builder names reach docker unchecked' test_buildx.sh \
    's@    buildx_name_ok "\$cur" || return 0@    :@'

check_mutation 'builders with no cache reported' test_buildx.sh \
    's@    \[ "\$kb" -gt 0 \] || return 0@    :@'

check_mutation 'a node with no cache decides the state' test_buildx.sh \
    's@        \[ "\$nkb" -ge 1024 \] || continue@        :@'

check_mutation 'what a prune leaves behind is offered again' test_buildx.sh \
    's@\[ "\$nkb" -ge 1024 \]@[ "$nkb" -gt 0 ]@'

check_mutation 'buildx caches not added to the docker row' test_buildx.sh \
    's@            if \[ "\$eng" = docker \]; then size=@            if false; then size=@'

check_mutation 'stopped builder pruned without starting it' test_buildx.sh \
    's@if ! bounded 60 docker buildx inspect --bootstrap "\$b" >/dev/null 2>&1; then@if false; then@'

check_mutation 'running builder started anyway' test_buildx.sh \
    's@        if \[ "\$state" = stopped \]; then@        if true; then@'

check_mutation 'stopped builder left running after the prune' test_buildx.sh \
    's@        \[ "\$state" = stopped \] || continue@        continue@'

check_mutation 'a builder that will not start is pruned anyway' test_buildx.sh \
    '/could not start builder/{n;s/continue/:/;}'

check_mutation 'buildx caches never pruned' test_buildx.sh \
    's@        if \[ "\$eng" = docker \]; then prune_buildx_caches; fi@        :@'

check_mutation 'buildx run for every engine' test_buildx.sh \
    's@        if \[ "\$eng" = docker \]; then prune_buildx_caches; fi@        prune_buildx_caches@'

check_mutation 'system prune runs before the builders' test_buildx.sh \
    's@        if \[ "\$eng" = docker \]; then prune_buildx_caches; fi@        "$eng" system prune -af >/dev/null 2>\&1; if [ "$eng" = docker ]; then prune_buildx_caches; fi@'

# ---- the restart estimate (docs/DESIGN.md#restart-estimate) -----------------
#
# Every part is measured against a fake the test controls, so each mutation
# below changes a number or a sentence the test pins exactly. The container
# rows are the ones a live machine could never catch: on a stock Mac $HOME and
# the VM volume always share disk3, so only a fixture can say what disk12 is.

check_mutation 'swap counted from a VM volume in another container' test_restart.sh \
    '/vm_dev%%/s/] || return 1$/] || :/'

check_mutation 'container read up to any digit (disk12 == disk1)' test_restart.sh \
    '/vm_dev%%/s/%%s\[\[:digit:\]\]\*/%%[[:digit:]]*/g'

check_mutation 'whole device names compared (disk3s5 != disk3s6)' test_restart.sh \
    '/vm_dev%%/s/%%s\[\[:digit:\]\]\*//g'

check_mutation 'VM row taken without checking its mount point' test_restart.sh \
    's@NR==3 && \$6=="/System/Volumes/VM" @NR==3 @'

check_mutation 'swap read from the Available column' test_restart.sh \
    's@{v=\$1; u=\$3}@{v=$1; u=$4}@'

check_mutation 'a non-numeric swap figure accepted' test_restart.sh \
    's@    case "\$vm_used" in ..|\*\[!0-9\]\*) return 1 ;; esac@    :@'

check_mutation 'a temp folder on another volume counted' test_restart.sh \
    '/= "\$home_dev" \] || continue/s/|| continue/|| :/'

check_mutation 'lsof filters ORed into every open file (no -a)' test_restart.sh \
    's@lsof -a -nP +L1@lsof -nP +L1@'

check_mutation 'every open handle counted, not every file' test_restart.sh \
    's@ && !(k in seen))@)@'

check_mutation 'deleted directories counted as files' test_restart.sh \
    's@if (t == "REG" && @if (@'

check_mutation 'holders ranked smallest first' test_restart.sh \
    's@sz\[j\] > sz\[b\]@sz[j] < sz[b]@'

check_mutation 'mount point cut at its first space' test_restart.sh \
    's@NR==2 {for (i = 6; i <= NF; i++) printf "%s%s", (i > 6 ? " " : ""), \$i}@NR==2 {print $6}@'

check_mutation 'restart line shown below 100 MiB' test_restart.sh \
    's@^RESTART_NOTE_MIN_KB=102400$@RESTART_NOTE_MIN_KB=0@'

check_mutation 'restart line floor back at 1 GiB' test_restart.sh \
    's@^RESTART_NOTE_MIN_KB=102400$@RESTART_NOTE_MIN_KB=1048576@'

check_mutation 'restart line shown when more is already free' test_restart.sh \
    's@    \[ "\$total" -ge "\$DISK_FREE_KB" \] || return 1@    :@'

check_mutation 'temp files left out of the total' test_restart.sh \
    's@local total=\$((DISK_SWAP_KB + DISK_TEMP_KB + DISK_HELD_KB))@local total=$((DISK_SWAP_KB + DISK_HELD_KB))@'

check_mutation 'holders named however little they hold' test_restart.sh \
    's@\[ "\$DISK_HELD_KB" -ge "\$RESTART_HOLDERS_MIN_KB" \] && \[ -n@[ -n@'

# The holders keep a floor of their own: from the note's 100 MiB, a daemon
# holding 150 MB would be named as something to quit.
check_mutation 'holders named from the note floor' test_restart.sh \
    's@\[ "\$DISK_HELD_KB" -ge "\$RESTART_HOLDERS_MIN_KB" \]@[ "$DISK_HELD_KB" -ge "$RESTART_NOTE_MIN_KB" ]@'

check_mutation 'refresh_restart_note keeps the last measurement' test_restart.sh \
    's@^    restart_stats$@    :@'

# The note's row in the menu. The frame is a fixed height, so each of these
# either loses the row or makes the frame taller than the window.
check_mutation 'the menu never shows the restart note' test_restart.sh \
    's@^    \[ -n "\$RESTART_NOTE" \] && show_note=1@    :@'

check_mutation 'the note row is left out of the chrome count' test_restart.sh \
    's@local viewport=\$((rows - 5 - keys_h - show_note))@local viewport=$((rows - 5 - keys_h))@'

check_mutation 'a short window keeps the note' test_restart.sh \
    's@\[ "\$viewport" -lt 3 \] && { show_note=0; viewport=\$((rows - 5 - keys_h)); }@:@'

check_mutation 'the note row is not clipped to the window' test_restart.sh \
    's@_clip_plain "↳ \$RESTART_NOTE" \$((cols - 1))@_CLIP="↳ $RESTART_NOTE"@'

# ---- sizing: one du per category (docs/DESIGN.md#sizing) ---------------------

check_mutation 'paths_kb keeps only the last du line' test_helpers.sh \
    "s@| awk '{ s += \$1 } END { print s + 0 }'@| awk '{ s = \$1 } END { print s + 0 }'@"

check_mutation 'paths_kb asks du for 512-byte blocks' test_helpers.sh \
    's@xargs -0 du -sk 2>/dev/null@xargs -0 du -s 2>/dev/null@'

check_mutation 'a category is sized from its first path only' test_helpers.sh \
    's@paths_kb "\${CAT_PATHS\[\$i\]}" > "\$SCAN_DIR/size_\$i"@du_kb "${CAT_PATHS[$i]%%$NL*}" > "$SCAN_DIR/size_$i"@'

# One is deliberately absent: dropping paths_kb's empty-list guard. Its job is to
# keep a bare `du -sk` — the current directory — from being run, but macOS's
# xargs runs nothing on empty input, so on the only OS cdm supports no input can
# tell the mutant apart. The guard stays for an xargs that does run (GNU's).
# Verified to survive rather than assumed.

# ---- the computed kinds' fields (docs/DESIGN.md#json-line-protocol) -----------

check_mutation 'JXA stops emitting CAND records' test_json.sh \
    "s@(c.candidates || \[\]).forEach(function(p){ out.push(tab('CAND', p)); });@@"

check_mutation 'JXA stops emitting DAYS records' test_json.sh \
    "s@if (c.idleDays != null) out.push(tab('DAYS', c.idleDays));@@"

check_mutation 'parser ignores CAND records' test_json.sh \
    's|            CAND) ccands=|            ZZCAND) ccands=|'

check_mutation 'parser ignores DAYS records' test_json.sh \
    's|            DAYS) cdays="\$rest" ;;|            ZZDAYS) cdays="$rest" ;;|'

check_mutation 'candidates leak into the next category' test_json.sh \
    's|cimages=""; ccands=""; cdays="" ;;|cimages=""; cdays="" ;;|'

check_mutation 'idleDays leak into the next category' test_json.sh \
    's|cimages=""; ccands=""; cdays="" ;;|cimages=""; ccands="" ;;|'

# ---- older-versions (docs/DESIGN.md#older-versions) ---------------------------
#
# Every one of these keeps something other than the newest version, or offers
# the newest itself. "Newest" is a version order a string sort gets wrong.

check_mutation 'older-versions kind unrecognised' test_older_versions.sh \
    's|^        older-versions)$|        zz-older-versions)|'

check_mutation 'versions compared as strings (9 above 10)' test_older_versions.sh \
    's@k = k substr(Z, 1, 20 - length(d)) d "."@k = k d "."@'

check_mutation 'only the first version field compared' test_older_versions.sh \
    's@for (j = 1; j <= 8; j++)@for (j = 1; j <= 1; j++)@'

check_mutation 'a pre-release outranks its release' test_older_versions.sh \
    's@((v != "" \&\& tail == "") ? "~" : "!")@((v != "" \&\& tail == "") ? "!" : "~")@'

check_mutation 'the newest version is offered too' test_older_versions.sh \
    's@\[ -n "\$m" \] \&\& \[ "\$m" != "\$newest" \] || continue@[ -n "$m" ] || continue@'

check_mutation 'a version two patterns reach is offered twice' test_older_versions.sh \
    's@            case "\$NL\$found\$NL" in \*"\$NL\$m\$NL"\*) continue ;; esac@            :@'

check_mutation 'register_older drops procs on the way to add_category' test_older_versions.sh \
    '/^register_older()/,/^}/ s@"\$default" "\$found" "" "\$procs"@"$default" "$found" ""@'

# One is deliberately absent: dropping the family-of-one guard
# (`case "$_GM" in *"$NL"*)`). A lone version is its own newest, so the
# `!= "$newest"` test below it already keeps it; the guard only saves an awk.
# Verified to survive rather than assumed.

# ---- android-idle-images (docs/DESIGN.md#android-idle-images) -----------------
#
# The one kind that offers an image an AVD boots from, so most of these offer
# one it must not: in use lately, booted by nothing, or aged by the wrong file.

check_mutation 'android-idle-images kind unrecognised' test_android_idle.sh \
    's|^        android-idle-images)$|        zz-android-idle-images)|'

check_mutation 'a recently started AVD does not keep its image' test_android_idle.sh \
    's@                \[ "\$last" -ge "\$cutoff" \] && recent=1@                :@'

check_mutation 'an image no AVD boots is offered as idle' test_android_idle.sh \
    's@            \[ -n "\$avds" \] && \[ "\$recent" -eq 0 \] || continue@            [ "$recent" -eq 0 ] || continue@'

check_mutation "config.ini's mtime counts as a start" test_android_idle.sh \
    's@        n == "config.ini" { c = \$1; next }@@'

check_mutation 'an AVD found twice is named twice' test_android_idle.sh \
    's@case ", \$avds, " in \*", \$an, "\*) ;; \*) avds="\${avds:+\$avds, }\$an" ;; esac@avds="${avds:+$avds, }$an"@'

check_mutation 'idle images offered without a usable idleDays' test_android_idle.sh \
    '/^register_idle_images()/,/^}/ s@    case "\$days" in ..|\*\[!0-9\]\*) return 0 ;; esac@    :@'

# ---- claude-transcripts (docs/DESIGN.md#claude-transcripts) -------------------

check_mutation 'claude-transcripts kind unrecognised' test_claude_history.sh \
    's|^        claude-transcripts)$|        zz-claude-transcripts)|'

check_mutation "transcripts take the rule's method and default" test_claude_history.sh \
    's@add_category "\$icon" "\$name" "\$desc" "trash" 0 "\$found"@add_category "$icon" "$name" "$desc" "rm" 1 "$found"@'

check_mutation 'a running session is offered' test_claude_history.sh \
    's@ || index(live, "|" id "|")@@'

check_mutation 'running sessions are never read' test_claude_history.sh \
    's@            \[ -n "\$id" \] && live="\$live\$id|"@            :@'

check_mutation 'a name that is not a session id is offered' test_claude_history.sh \
    's@if (length(id) != 36 || id !~ /^\[0-9a-fA-F-\]+\$/ || index@if (index@'

check_mutation "a session's folder is left behind" test_claude_history.sh \
    's@            s = substr(f, 1, length(f) - 6); if (s in D) print s@            s = ""@'

check_mutation 'fresh transcripts are offered' test_claude_history.sh \
    's@ -mtime +"\$days" 2>/dev/null | sed@ 2>/dev/null | sed@'

# One is deliberately absent: register_transcripts' idleDays guard. Without it an
# empty or non-numeric age reaches `find -mtime +…`, which refuses it and lists
# nothing — the same empty row the guard returns. Verified to survive rather
# than assumed; the guard keeps the refusal explicit. (register_idle_images'
# twin is mutated above: its age goes through $(( )), where it is not refused.)

# ---- the Claude Code history note (docs/DESIGN.md#claude-history) -------------

check_mutation 'the note ignores desktopSessionCleanupPeriodDays' test_claude_history.sh \
    "s@    grep -q '\"desktopSessionCleanupPeriodDays\"' \"\$settings\" 2>/dev/null \&\& return 1@    :@"

check_mutation "the note ignores the user's cleanupPeriodDays" test_claude_history.sh \
    's@\[ "\$v" -ge 1 \] && CLAUDE_KEEP_DAYS="\$v"@:@'

check_mutation 'the note counts every old .jsonl, not sessions' test_claude_history.sh \
    's@            length(id) == 36 && id ~ /^\[0-9a-fA-F-\]+\$/ { n++ }@            { n++ }@'

check_mutation 'the note shows with no old transcripts' test_claude_history.sh \
    's@    \[ "\$CLAUDE_OLD_N" -gt 0 \] || return 1@    :@'

check_mutation 'the note shows for a small history' test_claude_history.sh \
    's@^CLAUDE_NOTE_MIN_KB=1048576$@CLAUDE_NOTE_MIN_KB=0@'

check_mutation 'CLAUDE_CONFIG_DIR ignored' test_claude_history.sh \
    's@^CLAUDE_DIR="\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}"@CLAUDE_DIR="$HOME/.claude"@'

# ---- rust-toolchains (docs/DESIGN.md#rust-toolchains) -------------------------
#
# What is kept, what is matched as a pin, and that the clean is rustup's: rustup
# here is a function that logs what it is asked, so every call is pinned.

check_mutation 'rust-toolchains kind unrecognised' test_rust_toolchains.sh \
    's|^        rust-toolchains)$|        zz-rust-toolchains)|'

check_mutation 'stable is offered' test_rust_toolchains.sh \
    's@            case "\$tc" in stable-\*) continue ;; esac@            :@'

check_mutation 'the default toolchain is offered' test_rust_toolchains.sh \
    's@            \[ -n "\$def" \] && toolchain_is "\$tc" "\$def" && continue@            :@'

check_mutation 'a linked toolchain is offered' test_rust_toolchains.sh \
    's@\[ -n "\$m" \] && \[ -d "\$m" \] && \[ ! -L "\$m" \] || continue@[ -n "$m" ] \&\& [ -d "$m" ] || continue@'

check_mutation 'scanned toolchain names go unchecked' test_rust_toolchains.sh \
    's@            toolchain_name_ok "\$tc" || continue@            :@'

check_mutation 'toolchain_name_ok accepts a leading dash' test_rust_toolchains.sh \
    '/^toolchain_name_ok()/,/^}/ s@'"''"'|\[!\[:alnum:\]\]\*|@'"''"'|@'

check_mutation 'a channel matches a dated nightly' test_rust_toolchains.sh \
    's@    case "\$host" in \*-\*-\*-\*) return 1 ;; \*-apple-darwin) return 0 ;; esac@    case "$host" in *-apple-darwin) return 0 ;; esac@'

check_mutation 'a legacy rust-toolchain file is ignored' test_rust_toolchains.sh \
    's@in rust-toolchain) \[ -n@in zz-rust-toolchain) [ -n@'

check_mutation 'a quoted channel keeps its quotes' test_rust_toolchains.sh \
    's@\\"\*) v="\${v#\\"}"; v="\${v%%\\"\*}" ;;@\\"*) ;;@'

check_mutation "rustup's overrides are never read" test_rust_toolchains.sh \
    's@\[ "\$in_over" -eq 1 \] || continue@continue@'

check_mutation 'pins found under junk dirs (node_modules)' test_rust_toolchains.sh \
    's|            \[ -n "\$d" \] && names\[\${#names\[@\]}\]="\$d"|            :|'

check_mutation "pins found under the scan's pruned dirs" test_rust_toolchains.sh \
    's|    for d in \${SCAN_PRUNE\[@\]+"\${SCAN_PRUNE\[@\]}"}; do names|    for d in; do names|'

check_mutation 'pins never named on the row' test_rust_toolchains.sh \
    's@            by="\${by:+\$by, }\$dir"@            :@'

check_mutation 'rows offered with no rustup to remove them' test_rust_toolchains.sh \
    's@    RUSTUP_BIN=\$(rustup_bin) || { RUSTUP_BIN=""; return 0; }@    RUSTUP_BIN=$(rustup_bin)@'

check_mutation 'uninstall skips the name check' test_rust_toolchains.sh \
    's@        if ! toolchain_name_ok "\$tc" || ! is_safe_target "\$p"; then@        if ! is_safe_target "$p"; then@'

check_mutation 'uninstall skips the safety gate' test_rust_toolchains.sh \
    's@        if ! toolchain_name_ok "\$tc" || ! is_safe_target "\$p"; then@        if ! toolchain_name_ok "$tc"; then@'

check_mutation 'uninstall runs with no rustup known' test_rust_toolchains.sh \
    's@        if \[ -z "\$RUSTUP_BIN" \]; then echo@        if false; then echo@'

check_mutation 'rustup runs against the wrong rustup home' test_rust_toolchains.sh \
    's@        RUSTUP_HOME="\${p%/toolchains/\*}" "\$RUSTUP_BIN"@        "$RUSTUP_BIN"@'

check_mutation 'the clean never routes a toolchain to rustup' test_rust_toolchains.sh \
    's@            if \[ "\$method" = "rustup" \]; then run_rustup_uninstall "\${CAT_PATHS\[\$i\]}"; continue; fi@@'

check_mutation 'the plan calls a toolchain uninstall a DELETE' test_rust_toolchains.sh \
    's@            rustup)     tag=@            zzrustup)   tag=@'

check_mutation 'details call a toolchain uninstall a delete' test_rust_toolchains.sh \
    's@        rustup)     label=@        zzrustup)   label=@'

# ---- rust-docs (docs/DESIGN.md#rust-docs) ------------------------------------
#
# Offered only where rustup lists the component, and removed only by rustup. The
# lines register_rust_docs shares with scan_toolchains are addressed by range.

check_mutation 'rust-docs kind unrecognised' test_rust_docs.sh \
    's|^        rust-docs)$|        zz-rust-docs)|'

check_mutation 'docs offered without the component installed' test_rust_docs.sh \
    's@                case "\$line" in rust-docs-\*) has=1; break ;; esac@                has=1; break@'

check_mutation 'docs offered with no rustup to remove them' test_rust_docs.sh \
    '/^register_rust_docs()/,/^}/ s@    RUSTUP_BIN=\$(rustup_bin) || { RUSTUP_BIN=""; return 0; }@    RUSTUP_BIN=$(rustup_bin)@'

check_mutation 'docs toolchain names go unchecked' test_rust_docs.sh \
    '/^register_rust_docs()/,/^}/ s@            toolchain_name_ok "\$tc" || continue@            :@'

check_mutation "a linked toolchain's docs are offered" test_rust_docs.sh \
    '/^register_rust_docs()/,/^}/ s@\[ -n "\$m" \] && \[ -d "\$m" \] && \[ ! -L "\$m" \] || continue@[ -n "$m" ] \&\& [ -d "$m" ] || continue@'

check_mutation 'docs removal skips the name check' test_rust_docs.sh \
    's@ || ! toolchain_name_ok "\$tc" || ! is_safe_target "\$p"; then@ || ! is_safe_target "$p"; then@'

check_mutation 'docs removal skips the safety gate' test_rust_docs.sh \
    's@ || ! toolchain_name_ok "\$tc" || ! is_safe_target "\$p"; then@ || ! toolchain_name_ok "$tc"; then@'

check_mutation 'docs removal runs with no rustup known' test_rust_docs.sh \
    '/^run_rustup_docs_remove()/,/^}/ s@        if \[ -z "\$RUSTUP_BIN" \]; then echo@        if false; then echo@'

check_mutation 'docs removal runs against the wrong rustup home' test_rust_docs.sh \
    's@        RUSTUP_HOME="\${t%/toolchains/\*}" "\$RUSTUP_BIN" component@        "$RUSTUP_BIN" component@'

check_mutation 'the clean never routes docs to rustup' test_rust_docs.sh \
    's@            if \[ "\$method" = "rustdocs" \]; then run_rustup_docs_remove "\${CAT_PATHS\[\$i\]}"; continue; fi@@'

check_mutation 'the plan calls a docs removal a DELETE' test_rust_docs.sh \
    's@            rustdocs)   tag=@            zzrustdocs) tag=@'

check_mutation 'details call a docs removal a delete' test_rust_docs.sh \
    's@        rustdocs)   label=@        zzrustdocs) label=@'

# ---- code-sign-clones (docs/DESIGN.md#code-sign-clones) ----------------------
#
# What is kept, how the row is sized, and that the clean goes through the gate.
# ps is a shell function in the test, so every process list is pinned. A clone
# of unknown age (the `!~ /^[0-9]+$/ || == 0` test) is not listed: stat always
# reports an APFS birth time, so no fixture can produce one.

check_mutation 'code-sign-clones kind unrecognised' test_code_sign_clones.sh \
    's|^        code-sign-clones)$|        zz-code-sign-clones)|'

check_mutation "a running browser's copy is offered" test_code_sign_clones.sh \
    's@st\[k\] + 300) next@st[k] + 300) {}@'

check_mutation 'a launch in progress is offered' test_code_sign_clones.sh \
    's@ || now - \$1 < 300) next@) next@'

check_mutation 'no process list: copies offered anyway' test_code_sign_clones.sh \
    's@    \[ -n "\$starts" \] || return 0@    :@'

check_mutation 'start times ignore whole days' test_code_sign_clones.sh \
    's@now - (s + d \* 86400)@now - s@'

check_mutation 'copies sized by du' test_code_sign_clones.sh \
    's@                container|clones) echo@                container) echo@'

check_mutation 'a still-installed version counted as data' test_code_sign_clones.sh \
    's@if \[ -n "\$b2" \] && ! clone_version_shared "\$a" "\$b2"; then@if [ -n "$b2" ]; then@'

check_mutation "an old version's blocks not counted" test_code_sign_clones.sh \
    's@kb=\$((kb + \$(du_kb "\$sample")))@:@'

check_mutation 'clone delete skips the safety gate' test_code_sign_clones.sh \
    's@        if is_safe_target "\$p"; then rm -rf@        if true; then rm -rf@'

check_mutation 'the clean never routes clones' test_code_sign_clones.sh \
    's@            if \[ "\$method" = "clones" \]; then run_clone_delete "\${CAT_PATHS\[\$i\]}"; continue; fi@@'

check_mutation 'details du each copy' test_code_sign_clones.sh \
    's@    elif \[ "\${CAT_METHOD\[\$i\]}" = "clones" \]; then@    elif false; then@'

echo
printf 'mutations: %d, survived (holes in the tests): %d\n' "$total" "$survived"
if [ "$survived" -gt 0 ]; then
    echo 'FAIL — every surviving mutation is a bug the suite would not catch.'
    exit 1
fi
echo 'ok — the suite catches every mutation.'
