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
#     at least the free space, and both edges are asserted from each side.

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

# Parts under 1 MiB are left out of the sentence, not printed as "0 KB".
DISK_SWAP_KB=14680064; DISK_TEMP_KB=12; DISK_HELD_KB=0; DISK_HELD_APPS=""
assert_eq "A restart would free about 14.00 GB: 14.00 GB of swap" \
    "$(restart_line)" "empty parts are left out"

# The 1 GiB floor, both sides (free space held at 0 so only the floor decides).
DISK_FREE_KB=0; DISK_SWAP_KB=1048575; DISK_TEMP_KB=0
assert_fail "restart_line stays quiet below 1 GiB" restart_line
DISK_SWAP_KB=1048576
assert_ok "restart_line speaks at exactly 1 GiB" restart_line

# Against the free space, both sides: a restart that would free less than the
# disk already has free is not worth the line.
DISK_SWAP_KB=5242956; DISK_TEMP_KB=0; DISK_FREE_KB=5242957
assert_fail "restart_line stays quiet when free space exceeds it" restart_line
DISK_FREE_KB=5242956
assert_ok "restart_line speaks when it matches the free space" restart_line

test_summary
