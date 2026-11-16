#!/bin/bash
# mute_keys / unmute_keys / drain_keys (cdm) — keys typed while cdm is busy are
# not echoed and never reach the next prompt.
#
# What the assertions below are shaped around:
#
#   * the bug lives in a terminal, so the test needs one. A harness runs inside
#     `script -q /dev/null` (a real pty), sources cdm there — so cdm opens the
#     pty on fd 3 and `[ -t 3 ]` holds — and keys are written into the pty
#     through script's stdin. This works with no terminal on the outside, which
#     is how CI runs.
#   * no sleeps race the keystrokes: the harness touches a file when it is
#     ready for a key and the feeder waits for that file before typing, so a
#     slow machine is slower, not flaky.
#   * every "nothing came through" row has a premise row that shows the same
#     key DOES come through (and IS echoed) without the mute. Without it a
#     broken harness — a key that never arrives at all — would pass every
#     assertion here for free.
#   * the terminal state is compared with `stty -g` minus PENDIN: the kernel
#     sets that flag itself whenever ICANON is switched back on, and clears it
#     on the next read. It is not ours to restore. see docs/DESIGN.md#typeahead
#   * outside a pty (fd 3 not a terminal) and under -y (NON_INTERACTIVE=1) the
#     functions must not touch the terminal at all: a backgrounded `cdm -y &`
#     calling stty would be stopped by SIGTTOU.
#   * unmute_keys's cat only returns on its own under MIN 0 TIME 0; in line mode
#     it waits for a whole line. Under sudo it met one twice: a run started in
#     the background of its pty gets EINTR from its first stty, and sudo puts
#     its own terminal's modes back on the pty when it is continued. A stty
#     shell function fakes the first; the second resets the pty by hand, under
#     a watchdog so a waiting cat fails the test instead of hanging it.

. "$(dirname "$0")/lib.sh"

T_DIR="$HOME/typeahead"
mkdir -p "$T_DIR/home" || exit 1
T_RES="$T_DIR/results"
T_HARNESS="$T_DIR/harness.sh"

cat > "$T_HARNESS" <<'HARNESS'
# Runs inside the pty. $1 = cdm, $2 = sandbox HOME, $3 = sync/results dir.
CDM_BIN="$1"; export HOME="$2"; S="$3"
set --
CDM_LIB=1 . "$CDM_BIN"
R="$S/results"
# st — the terminal's settings, minus PENDIN (kernel-owned, see the test header).
st() {
    local g lf
    g=$(stty -g <&3 2>/dev/null)
    lf=${g#*:lflag=}; lf=${lf%%:*}
    printf '%s' "${g/:lflag=$lf:/:lflag=$(printf '%x' $(( 0x$lf & ~0x20000000 ))):}"
}
# wait_key <n> — ask the feeder for key <n>, give the pty time to deliver it.
wait_key() { touch "$S/ready$1"; sleep 0.5; }
got() { local k=""; if IFS= read -r -s -n 1 -t 1 k <&3; then echo "GOT[$k]"; else echo NONE; fi; }

printf 'ECHO1<'; wait_key 1; printf '>\n'
echo "premise=$(got)" >> "$R"

before=$(st)
mute_keys
printf 'ECHO2<'; wait_key 2; printf '>\n'
unmute_keys
echo "muted=$(got)" >> "$R"
[ "$(st)" = "$before" ] && echo "restored=yes" >> "$R" || echo "restored=no" >> "$R"

printf 'ECHO3<'; wait_key 3; printf '>\n'
drain_keys
echo "drained=$(got)" >> "$R"

mute_keys
cleanup_on_exit >/dev/null 2>&1
[ "$(st)" = "$before" ] && echo "exit_restored=yes" >> "$R" || echo "exit_restored=no" >> "$R"
echo "exit_saved=[$KEYS_SAVED]" >> "$R"

# A mute that did not take saves nothing, so unmute_keys has nothing to drain: its
# cat must never meet a terminal still in line mode.
stty() { case " $* " in *' -icanon '*) return 1 ;; esac; command stty "$@"; }
mute_keys
unset -f stty
echo "failed_saved=[$KEYS_SAVED]" >> "$R"
[ "$(st)" = "$before" ] && echo "failed_untouched=yes" >> "$R" || echo "failed_untouched=no" >> "$R"

# The first stty fails and the second takes: what a run started in the background
# of its terminal (sudo starts one that way) sees once it is brought to the front.
t_n=0
stty() { case " $* " in *' -icanon '*) t_n=$((t_n + 1)); [ "$t_n" -eq 1 ] && return 1 ;; esac; command stty "$@"; }
mute_keys
unset -f stty
[ -n "$KEYS_SAVED" ] && echo "retry_saved=yes" >> "$R" || echo "retry_saved=no" >> "$R"
case " $(stty -a <&3 | tr '\n' ' ') " in *' -icanon '*' -echo '*) echo "retry_muted=yes" ;; *) echo "retry_muted=no" ;; esac >> "$R"
unmute_keys

# The terminal put back in line mode while muted (sudo copies its own terminal's
# modes onto the run's pty when it is continued after a stop): unmute_keys must
# still drop the key and return, not wait in cat for a whole line. The watchdog
# frees a cat that waits.
mute_keys
stty icanon echo <&3 2>/dev/null
case " $(stty -a <&3 | tr '\n' ' ') " in *' icanon '*) echo "reset_premise=line" ;; *) echo "reset_premise=other" ;; esac >> "$R"
printf 'ECHO4<'; wait_key 4; printf '>\n'
( unmute_keys ) &
t_job=$!
i=0
while kill -0 "$t_job" 2>/dev/null && [ "$i" -lt 60 ]; do sleep 0.05; i=$((i + 1)); done
if kill -0 "$t_job" 2>/dev/null; then
    echo "reset_unmute=hung" >> "$R"
    pkill -P "$t_job" 2>/dev/null; kill "$t_job" 2>/dev/null
    stty "$KEYS_SAVED" <&3 2>/dev/null
else
    echo "reset_unmute=returned" >> "$R"
fi
wait "$t_job" 2>/dev/null
KEYS_SAVED=""        # the subshell gave the terminal back; this copy is stale
echo "reset_drained=$(got)" >> "$R"
[ "$(st)" = "$before" ] && echo "reset_restored=yes" >> "$R" || echo "reset_restored=no" >> "$R"

NON_INTERACTIVE=1
mute_keys
[ "$(st)" = "$before" ] && echo "y_untouched=yes" >> "$R" || echo "y_untouched=no" >> "$R"
echo "y_saved=[$KEYS_SAVED]" >> "$R"
echo done >> "$R"
touch "$S/ready_end"
HARNESS

: > "$T_RES"
# feed <n> <key> — type <key> once the harness asks for key <n>.
feed() {
    local i=0
    while [ ! -e "$T_DIR/ready$1" ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done
    printf '%s' "$2"
}
T_OUT=$( { feed 1 Q; feed 2 Z; feed 3 W; feed 4 R; feed _end ''; } \
    | script -q /dev/null /bin/bash "$T_HARNESS" "$CDM_BIN" "$T_DIR/home" "$T_DIR" 2>&1 | tr -d '\r')

res() { sed -n "s/^$1=//p" "$T_RES"; }

assert_eq done "$(tail -n 1 "$T_RES")" 'the pty harness ran to the end'

# ---- premise: without the mute, a key typed while busy is read and echoed ---
assert_eq 'GOT[Q]' "$(res premise)" 'premise: an unmuted key typed while busy reaches the next read'
case "$T_OUT" in *'ECHO1<Q>'*) r=echoed ;; *) r="not echoed: $T_OUT" ;; esac
assert_eq echoed "$r" 'premise: an unmuted key typed while busy is echoed'

# ---- muted: not echoed, dropped, terminal given back ------------------------
assert_eq NONE "$(res muted)" 'a key typed while muted never reaches the next read'
case "$T_OUT" in *'ECHO2<>'*) r=silent ;; *) r="echoed: $T_OUT" ;; esac
assert_eq silent "$r" 'a key typed while muted is not echoed'
assert_eq yes "$(res restored)" 'unmute_keys restores the terminal as it was'

# ---- drain_keys: a prompt only takes keys typed after it is shown -----------
assert_eq NONE "$(res drained)" 'drain_keys drops a key queued before the prompt'

# ---- exit: cleanup_on_exit gives the terminal back --------------------------
assert_eq yes "$(res exit_restored)" 'cleanup_on_exit restores the terminal after mute_keys'
assert_eq '[]' "$(res exit_saved)" 'cleanup_on_exit forgets the saved state'

# ---- a mute that did not take: nothing saved, so nothing to drain ------------
assert_eq '[]' "$(res failed_saved)" 'a mute that did not take saves nothing, so unmute_keys drains nothing'
assert_eq yes "$(res failed_untouched)" 'a mute that did not take leaves the terminal as it was'

# ---- the first stty fails, the second takes (a run started in the background) --
assert_eq yes "$(res retry_saved)" 'mute_keys tries again when its first stty fails'
assert_eq yes "$(res retry_muted)" '...and the terminal ends up muted'

# ---- the terminal put back in line mode while muted ----------------------------
assert_eq line "$(res reset_premise)" 'premise: the reset put the terminal back in line mode'
assert_eq returned "$(res reset_unmute)" 'unmute_keys returns when the terminal was reset to line mode'
assert_eq NONE "$(res reset_drained)" '...and drops the key typed meanwhile'
assert_eq yes "$(res reset_restored)" '...and restores the terminal'

# ---- -y never touches the terminal -----------------------------------------
assert_eq yes "$(res y_untouched)" 'NON_INTERACTIVE=1: mute_keys leaves the terminal alone'
assert_eq '[]' "$(res y_saved)" 'NON_INTERACTIVE=1: mute_keys saves nothing'

# ---- no terminal on fd 3: all three are no-ops ------------------------------
exec 3< /dev/null
KEYS_SAVED=""
assert_ok 'mute_keys succeeds with no terminal' mute_keys
assert_eq '' "$KEYS_SAVED" 'mute_keys saves nothing with no terminal'
assert_ok 'unmute_keys succeeds with no terminal' unmute_keys
assert_ok 'drain_keys succeeds with no terminal' drain_keys
assert_eq '' "$KEYS_SAVED" 'drain_keys saves nothing with no terminal'

test_summary
