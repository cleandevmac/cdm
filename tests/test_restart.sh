#!/bin/bash
# The restart estimate (docs/DESIGN.md#restart-estimate): swap_stats,
# temp_stats, held_stats and restart_line — the one line that says how much of a
# full disk only a restart, or quitting an app, can give back.
#
# What the assertions below are shaped around:
#
#   * every part is read from a command this file fakes — df, du and lsof are
#     shell functions here — because every one of them moves on a live machine,
#     and an assertion loose enough not to flake against a moving swap size is
#     loose enough to miss a wrong column.
#   * swap is the VM volume's own Used column, counted only when that volume
#     shares $HOME's APFS container. disk3s5 and disk3s6 are both disk3's, but
#     disk12 is not disk1: the fixture pairs are chosen so a container test that
#     strips too much, too little or nothing at all fails one of them.
#   * lsof lists one row per open HANDLE, so a deleted file three processes
#     share appears three times and must count once. Without -a the real lsof
#     ORs its two filters into every open file on the volume; the fake answers
#     that way too, so dropping -a is visible rather than harmless.
#   * restart_line shows only when the total is at least RESTART_NOTE_MIN_KB AND
#     at least the free space, and both edges are asserted from each side. The
#     apps holding deleted files are named from a floor of their own,
#     RESTART_HOLDERS_MIN_KB: below 1 GiB they are daemons nobody can quit.
#   * the menu repeats the line in a row under its status row. The frame is a
#     fixed height, so that row has to be counted in the chrome and shed first
#     in a short window — every frame below is measured, not eyeballed.

. "$(dirname "$0")/lib.sh"

# ---- fakes -------------------------------------------------------------------

# df: the header, then one row per path argument, looked up in t_df_rows
# ("path|row" lines). Flags are ignored.
t_df_rows=""
df() {
    local a p r
    echo 'Filesystem 1024-blocks Used Available Capacity Mounted on'
    for a in "$@"; do
        case "$a" in -*) continue ;; esac
        while IFS='|' read -r p r; do
            [ "$p" = "$a" ] && printf '%s\n' "$r"
        done <<EOF
$t_df_rows
EOF
    done
}

# du -skx <dir>: the KiB t_du_rows ("dir|kb" lines) gives that dir.
t_du_rows=""
du() {
    local d="${!#}" p k
    while IFS='|' read -r p k; do
        [ "$p" = "$d" ] && printf '%s\t%s\n' "$k" "$d"
    done <<EOF
$t_du_rows
EOF
}

# lsof: t_lsof when asked for deleted files (-a and +L1) on t_lsof_mnt, and
# t_lsof_all — every open file — when either filter is missing.
t_lsof=""; t_lsof_all=""; t_lsof_mnt=""
lsof() {
    case " $* " in
        *" -a "*" +L1 "*) [ "${!#}" = "$t_lsof_mnt" ] && printf '%s\n' "$t_lsof" ;;
        *) printf '%s\n' "$t_lsof_all" ;;
    esac
    return 0
}

DATA='/dev/disk3s5 239362496 201326592 445644 100% /System/Volumes/Data'
VM='/dev/disk3s6 239362496 14680064 445644 98% /System/Volumes/VM'

# ---- swap_stats ----------------------------------------------------------------

# A full 228 GB Mac with 14 GiB of swap: the shape it had before a restart gave
# back 36 GB of it.
t_df_rows="$HOME|$DATA
/System/Volumes/VM|$VM"
assert_ok "swap_stats reads a same-container VM volume" swap_stats
swap_stats
assert_eq "14680064" "$DISK_SWAP_KB" "swap is the VM volume's Used column, in KiB"

# A home on another disk: its "used" does not hold this swap.
t_df_rows="$HOME|/dev/disk5s1 976762584 500000000 476762584 52% /Volumes/Work
/System/Volumes/VM|$VM"
assert_fail "swap_stats refuses a VM volume in another container" swap_stats
swap_stats
assert_eq "0" "$DISK_SWAP_KB" "another container's swap counts as 0"

# disk12 is not disk1 — the container is the WHOLE disk number.
t_df_rows="$HOME|/dev/disk12s5 239362496 201326592 445644 100% /System/Volumes/Data
/System/Volumes/VM|/dev/disk1s6 239362496 14680064 445644 98% /System/Volumes/VM"
swap_stats
assert_eq "0" "$DISK_SWAP_KB" "disk12s5 and disk1s6 are different containers"

# A path df resolved to the root volume is not the VM volume, whatever it holds.
t_df_rows="$HOME|$DATA
/System/Volumes/VM|/dev/disk3s1s1 239362496 12582912 445644 97% /"
swap_stats
assert_eq "0" "$DISK_SWAP_KB" "a third row mounted elsewhere is not swap"

# No VM volume at all (df wrote its error to stderr).
t_df_rows="$HOME|$DATA"
assert_fail "swap_stats refuses a missing VM volume" swap_stats

t_df_rows="$HOME|$DATA
/System/Volumes/VM|/dev/disk3s6 239362496 N/A 445644 98% /System/Volumes/VM"
swap_stats
assert_eq "0" "$DISK_SWAP_KB" "a non-numeric Used column is refused"

# ---- temp_stats ----------------------------------------------------------------

mkdir -p "$HOME/T" "$HOME/tmp"
BOOT_TEMP_DIRS=("$HOME/T/" "$HOME/tmp")
t_du_rows="$HOME/T/|2097152
$HOME/tmp|1048576"

t_df_rows="$HOME|$DATA
$HOME/T/|$DATA
$HOME/tmp|$DATA"
temp_stats
assert_eq "3145728" "$DISK_TEMP_KB" "both boot-emptied temp folders are summed"

# A temp folder on another volume is not in this disk's "used".
t_df_rows="$HOME|$DATA
$HOME/T/|$DATA
$HOME/tmp|/dev/disk9s1 1000000 1000 999000 1% /Volumes/Scratch"
temp_stats
assert_eq "2097152" "$DISK_TEMP_KB" "a temp folder on another volume is left out"

# A missing folder, and a du that answered nothing (killed by bounded).
BOOT_TEMP_DIRS=("$HOME/T/" "$HOME/not-there")
t_du_rows=""
t_df_rows="$HOME|$DATA
$HOME/T/|$DATA"
temp_stats
assert_eq "0" "$DISK_TEMP_KB" "no answer from du counts as 0, not as an error"

# ---- held_stats ----------------------------------------------------------------

# lsof -F output, in the field order the real one prints. One plist cache is
# shared by two processes; Chrome holds one deleted 3 GiB file on two fds and a
# deleted directory; node holds a 1 GiB file.
t_lsof='p1317
cloginwindow
ftxt
tREG
D0x1000010
s72984
i98761291
n/Library/Preferences/Logging/.plist-cache.Cj6gIpVn
p1355
cdistnoted
ftxt
tREG
D0x1000010
s72984
i98761291
n/Library/Preferences/Logging/.plist-cache.Cj6gIpVn
p2001
cGoogle Chrome
f41
tREG
D0x1000010
s3221225472
i555
n/private/var/folders/xx/T/blob
f42
tREG
D0x1000010
s3221225472
i555
n/private/var/folders/xx/T/blob
f7
tDIR
D0x1000010
s4096
i556
n/private/tmp/gone
p3003
cnode
f19
tREG
D0x1000010
s1073741824
i777
n/private/tmp/task.output'
t_lsof_all='p1
czsh
ftxt
tREG
D0x1000010
s999999999999
i1
n/bin/zsh'
t_lsof_mnt="/System/Volumes/Data"
t_df_rows="$HOME|$DATA"

assert_ok "held_stats reads lsof" held_stats
held_stats
# 72984 + 3221225472 + 1073741824 bytes, each file once, in whole KiB.
assert_eq "4194375" "$DISK_HELD_KB" "each deleted file counts once, directories not at all"
assert_eq "Google Chrome, node, loginwindow" "$DISK_HELD_APPS" "the three biggest holders, biggest first"

# The volume's mount point may hold spaces; lsof must be handed all of it.
t_df_rows="$HOME|/dev/disk5s1 976762584 500000000 476762584 52% /Volumes/Work Disk"
t_lsof_mnt="/Volumes/Work Disk"
held_stats
assert_eq "4194375" "$DISK_HELD_KB" "a mount point with a space reaches lsof whole"

t_lsof=""
held_stats
assert_eq "0|" "$DISK_HELD_KB|$DISK_HELD_APPS" "no deleted files is 0 and no holders"

# ---- restart_line ----------------------------------------------------------------

# The full Mac from above: 14 GB of swap, 20.1 GB in the temp folders, 2.1 GB
# held by two apps, 0.4 GB free.
DISK_FREE_KB=445644
DISK_SWAP_KB=14680064; DISK_TEMP_KB=21076377; DISK_HELD_KB=2202010
DISK_HELD_APPS="Google Chrome, node"
assert_eq "A restart would free about 36.20 GB: 14.00 GB of swap, 20.10 GB of temp files, 2.10 GB of deleted files still held open by Google Chrome, node — quitting them frees that part now" \
    "$(restart_line)" "restart_line names every part, and the apps holding deleted files"

# Holders are named only when quitting them would matter.
DISK_HELD_KB=43442; DISK_HELD_APPS="linkd, sharingd, Google Chrome"
assert_eq "A restart would free about 34.14 GB: 14.00 GB of swap, 20.10 GB of temp files, 42 MB of deleted files still held open" \
    "$(restart_line)" "a small held part names no apps"
# Over the note's own 100 MiB floor but under the holders' 1 GiB one: still no names.
DISK_HELD_KB=524288
assert_eq "A restart would free about 34.60 GB: 14.00 GB of swap, 20.10 GB of temp files, 512 MB of deleted files still held open" \
    "$(restart_line)" "a held part under 1 GiB names no apps, whatever the note's floor"
DISK_HELD_KB=1048576
assert_eq "A restart would free about 35.10 GB: 14.00 GB of swap, 20.10 GB of temp files, 1.00 GB of deleted files still held open by linkd, sharingd, Google Chrome — quitting them frees that part now" \
    "$(restart_line)" "a held part of exactly 1 GiB names its apps"

# Parts under 1 MiB are left out of the sentence, not printed as "0 KB".
DISK_SWAP_KB=14680064; DISK_TEMP_KB=12; DISK_HELD_KB=0; DISK_HELD_APPS=""
assert_eq "A restart would free about 14.00 GB: 14.00 GB of swap" \
    "$(restart_line)" "empty parts are left out"

# The 100 MiB floor, both sides (free space held at 0 so only the floor decides).
DISK_FREE_KB=0; DISK_SWAP_KB=102399; DISK_TEMP_KB=0; DISK_HELD_KB=0
assert_fail "restart_line stays quiet below 100 MiB" restart_line
DISK_SWAP_KB=102400
assert_ok "restart_line speaks at exactly 100 MiB" restart_line

# Against the free space, both sides: a restart that would free less than the
# disk already has free is not worth the line.
DISK_SWAP_KB=5242956; DISK_TEMP_KB=0; DISK_FREE_KB=5242957
assert_fail "restart_line stays quiet when free space exceeds it" restart_line
DISK_FREE_KB=5242956
assert_ok "restart_line speaks when it matches the free space" restart_line

# ---- refresh_restart_note ------------------------------------------------------
#
# What the main flow and the rescan call: measure again, keep the line. The fakes
# above still describe the full Mac, so the swap comes back from df rather than
# from a global this file set by hand.
t_df_rows="$HOME|$DATA
/System/Volumes/VM|$VM"
t_du_rows=""; t_lsof=""; BOOT_TEMP_DIRS=()
DISK_FREE_KB=445644; DISK_SWAP_KB=0; DISK_TEMP_KB=0; DISK_HELD_KB=0
refresh_restart_note
assert_eq "A restart would free about 14.00 GB: 14.00 GB of swap" "$RESTART_NOTE" \
    "refresh_restart_note measures, then keeps the line"
DISK_FREE_KB=99999999
refresh_restart_note
assert_eq "" "$RESTART_NOTE" "refresh_restart_note clears a line that no longer applies"

# ---- the note in the menu ---------------------------------------------------------
#
# render_menu repaints a frame exactly TERM_ROWS lines tall when the list
# overflows; the note is one more line of chrome. Thirty rows overflow every size
# used here. Escapes are stripped so each line is what the terminal shows.
t_frame() {
    TERM_ROWS="$1"; TERM_COLS="$2"; SIZE_STALE=0
    render_menu | sed "s/$(printf '\033')\[[0-9;?]*[A-Za-z]//g"
}
t_lines() { t_frame "$1" "$2" | awk 'END { print NR }'; }
t_items() { t_frame "$1" "$2" | grep -c '\[ \]'; }
t_widest() {
    local l w=0
    while IFS= read -r l; do dwidth "$l"; [ "$_DW" -gt "$w" ] && w=$_DW; done <<EOF
$(t_frame "$1" "$2")
EOF
    echo "$w"
}
CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=(); CAT_PATHS=()
CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=(); CAT_PROCS=(); N=0
t_i=0
while [ "$t_i" -lt 30 ]; do
    add_category "x" "row $t_i" "desc $t_i" rm 0 "/nowhere/$t_i"; CAT_KB[$t_i]=$((1000 + t_i))
    t_i=$((t_i + 1))
done
CURSOR=0; SCROLL=0; DRY_RUN=0
DISK_TOTAL_KB=239362496; DISK_USED_KB=238916852; DISK_FREE_KB=445644

RESTART_NOTE=""
assert_eq "24" "$(t_lines 24 100)" "no note: the frame is the window's height"
assert_eq "18" "$(t_items 24 100)" "no note: 24 rows less six of chrome"

RESTART_NOTE="A restart would free about 36.20 GB: 14.00 GB of swap, 20.10 GB of temp files, 2.10 GB of deleted files still held open by Google Chrome, node — quitting them frees that part now"
assert_eq "↳ $RESTART_NOTE" "$(t_frame 24 300 | sed -n 3p)" "the note is the row under the status row"
assert_eq "24" "$(t_lines 24 100)" "with the note the frame is still the window's height"
assert_eq "17" "$(t_items 24 100)" "the note takes its row from the list"
assert_ok "a long note is clipped to the window" test "$(t_widest 24 100)" -le 100

# A short window sheds the note before anything else: at 10 rows it still fits
# beside a three-row list, at 8 it goes and the description goes after it.
assert_eq "10" "$(t_lines 10 100)" "10 rows: the frame fits"
assert_eq "1" "$(t_frame 10 100 | grep -c '↳')" "10 rows: the note is kept"
assert_eq "8" "$(t_lines 8 100)" "8 rows: the frame still fits"
assert_eq "0" "$(t_frame 8 100 | grep -c '↳')" "8 rows: the note is shed"

test_summary
