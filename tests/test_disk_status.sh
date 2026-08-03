#!/bin/bash
# The disk-status block (disk_stats, disk_used_pct, disk_line), total_kb, and
# the menu's status row (build_status_line) — everything behind the two numbers
# a user reads before and after a clean.
#
# What the assertions below are shaped around:
#
#   * disk_stats parses df's output, so most of this file runs against a FAKE
#     df defined partway down: a live volume's free space moves between two
#     calls, and an assertion loose enough not to flake against a moving number
#     is also loose enough to miss a wrong COLUMN. The fake pins the columns,
#     the record, the derivation and every refusal exactly. The price is that a
#     fake df ignores flags, so the one thing it cannot see is the -k — which is
#     why the real-df rows run FIRST, above the fake, and pin the unit against
#     the actual filesystem. Order is load-bearing here; see the banner below.
#   * used is DERIVED as total - available, never read from df's "Used" column:
#     on APFS the two do not reconcile (snapshots, purgeable space, the sibling
#     read-only system volume), and three numbers printed side by side have to
#     add up. Every fixture asserts used + free == total for that reason.
#   * every refusal leaves the three globals at 0 rather than half-set. The menu
#     row and the post-clean report both key off DISK_TOTAL_KB > 0 to decide
#     whether the numbers exist at all, so a partial parse would print a row
#     claiming a 0 KB disk.
#   * disk_line FORMATS, it does not refresh. Callers use it inside $(...),
#     where a refresh would set the globals in the subshell and lose them —
#     the same trap compute_sizes_write documents. The fabricated-globals row
#     is what pins that: it can only pass if disk_line never calls disk_stats.
#   * build_status_line degrades by tier like build_keys_line, and for the same
#     reason: the status row is one line of a fixed-height frame, so a row that
#     wraps makes the frame taller than the screen and scrolls it on every
#     repaint. Both the exact strings and the width bound are asserted, at the
#     boundary column on each side.
#   * _SS and _SP must stay in lockstep — _SP is the plain shadow that gets
#     measured, and a segment added to one and not the other silently mis-sizes
#     the row. Asserted by stripping the escapes from _SS rather than by
#     re-deriving _SP, so the assertion cannot drift with it.

. "$(dirname "$0")/lib.sh"

# ---- local helpers ---------------------------------------------------------

t_is_int() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
# t_strip <styled> — the same string with every SGR escape removed, i.e. what
# _SP is supposed to be. Works under --no-color too, where there is nothing to
# strip and the two are already equal.
t_strip() { printf '%s' "$1" | sed "s/$(printf '\033')\[[0-9;]*m//g"; }
t_trio() { printf '%s|%s|%s' "$DISK_TOTAL_KB" "$DISK_USED_KB" "$DISK_FREE_KB"; }

# ===========================================================================
# REAL df — these rows must run BEFORE the fake df is defined below.
# ===========================================================================
#
# Everything the fake cannot see: that df is asked for KiB (a `-Pm` or a
# default-blocks call still returns plausible integers, just off by a factor of
# 1024 or 2), and that the whole thing works against a live filesystem at all.
# Capacity is the stable column — free space moves under a running machine,
# total does not — so the unit is pinned on that one.

assert_ok "disk_stats succeeds on a real volume" disk_stats
disk_stats
assert_ok "total is a bare integer"     t_is_int "$DISK_TOTAL_KB"
assert_ok "used is a bare integer"      t_is_int "$DISK_USED_KB"
assert_ok "free is a bare integer"      t_is_int "$DISK_FREE_KB"
assert_ok "a real volume has a nonzero capacity" test "$DISK_TOTAL_KB" -gt 0
assert_ok "free never exceeds total"    test "$DISK_FREE_KB" -le "$DISK_TOTAL_KB"
assert_eq "$DISK_TOTAL_KB" "$((DISK_USED_KB + DISK_FREE_KB))" \
    "used + free == total on a real volume"

# The unit. df -k reports KiB; without it macOS reports 512-byte blocks, and -m
# reports MiB — both leave a plausible integer in place, and every size cdm
# prints would be off by a constant factor with nothing to show for it.
t_df_total=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $2}')
assert_eq "$t_df_total" "$DISK_TOTAL_KB" "capacity is read in KiB, from \$HOME's volume"

# ===========================================================================
# FAKE df — every row past this point is deterministic.
# ===========================================================================
#
# A shell function shadows the external command for the rest of this file, so
# disk_stats parses a table this test controls. Flags are ignored, which is the
# whole reason the -k rows above had to come first.

t_df_out=""
t_df_rc=0
df() { [ -n "$t_df_out" ] && printf '%s\n' "$t_df_out"; return "$t_df_rc"; }

# A normal volume: capacity 1000000 KiB, 700000 used per df, 250000 available.
# The three numbers deliberately do NOT reconcile — that is what APFS looks
# like — so reading df's "Used" column instead of deriving it is visible here.
t_df_out='Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/disk1s5 1000000 700000 250000 74% /System/Volumes/Data'

assert_ok "disk_stats parses a normal df table" disk_stats
disk_stats
assert_eq "1000000|750000|250000" "$(t_trio)" \
    "total from column 2, free from column 4, used derived from the pair"

assert_eq "75" "$(disk_used_pct)" "disk_used_pct on a 3/4-full volume"
assert_eq "977 MB total · 732 MB used (75%) · 244 MB free" "$(disk_line)" \
    "disk_line renders the trio in order, through human_kb, with the percentage"

# Rounding, both sides of .5 — a truncating percentage reads 71% for a volume
# that is 71.5% full, which is the one digit on that row.
DISK_TOTAL_KB=1000; DISK_USED_KB=715; DISK_FREE_KB=285
assert_eq "72" "$(disk_used_pct)" "disk_used_pct rounds 71.5% up"
DISK_USED_KB=714; DISK_FREE_KB=286
assert_eq "71" "$(disk_used_pct)" "disk_used_pct rounds 71.4% down"

# Divide-by-zero guard: the percentage is asked for before df has ever been
# read on the no-disk path below.
DISK_TOTAL_KB=0; DISK_USED_KB=0; DISK_FREE_KB=0
assert_eq "0" "$(disk_used_pct)" "disk_used_pct with no measurement yet"

# disk_line formats the globals and refreshes nothing. Fabricated values no real
# volume would produce, so a disk_line that re-read df could not coincide with
# them — this is the row that pins the $(...) safety.
DISK_TOTAL_KB=2097152; DISK_USED_KB=1048576; DISK_FREE_KB=1048576
assert_eq "2.00 GB total · 1.00 GB used (50%) · 1.00 GB free" "$(disk_line)" \
    "disk_line reads the globals rather than re-running df"

# And it prints NOTHING, and fails, when there is no measurement — the caller
# uses that to leave the line out entirely rather than print a 0 KB disk.
DISK_TOTAL_KB=0; DISK_USED_KB=0; DISK_FREE_KB=0
assert_eq "" "$(disk_line)" "disk_line prints nothing without a measurement"
assert_fail "disk_line reports failure without a measurement" disk_line

# ---- refusals: every one leaves the trio at 0 ------------------------------

# A header and nothing else — the volume vanished, or df wrote to stderr.
t_df_out='Filesystem 1024-blocks Used Available Capacity Mounted on'
assert_fail "disk_stats refuses a header-only table" disk_stats
disk_stats
assert_eq "0|0|0" "$(t_trio)" "a header-only table leaves the trio at 0"

# Nothing at all, and a non-zero status: df not found, or a path it cannot stat.
t_df_out=''; t_df_rc=1
assert_fail "disk_stats refuses empty df output" disk_stats
disk_stats
assert_eq "0|0|0" "$(t_trio)" "empty df output leaves the trio at 0"
t_df_rc=0

# The row df writes WITHOUT -P: a device name too long for the column pushes
# the numbers onto the next line. cdm passes -P so this cannot happen, and the
# refusal is what the parse does if it ever did — no numbers on record 2 means
# no answer, rather than a size invented from a device name.
t_df_out='Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/disk1s5-a-very-long-device-name-that-wraps
             1000000 700000 250000 74% /System/Volumes/Data'
assert_fail "disk_stats refuses a wrapped (non-POSIX) row" disk_stats
disk_stats
assert_eq "0|0|0" "$(t_trio)" "a wrapped row leaves the trio at 0"

# Non-numeric where a size belongs. Both columns are guarded and each needs its
# own fixture: an automount row (`map -hosts`, which df really does print) puts
# a word where the capacity goes, while a row with a real capacity and a dash
# for available reaches only the second guard.
t_df_out='Filesystem 1024-blocks Used Available Capacity Mounted on
map -hosts 0 0 0 100% /net'
assert_fail "disk_stats refuses an automount row with a word for a capacity" disk_stats

t_df_out='Filesystem 1024-blocks Used Available Capacity Mounted on
auto_home 1000000 700000 - 100% /System/Volumes/Data/home'
assert_fail "disk_stats refuses a row whose available is not a number" disk_stats

# Both guards accept bare decimal digits and nothing else — NOT "whatever bash
# arithmetic can parse". These two rows are the difference: 0x10 evaluates to 16
# inside $(( )) and passes a `-gt` comparison, so a field that reached the
# arithmetic unchecked would be silently accepted as a 16 KiB volume. df's
# output is data, and the numbers printed from it have to be the ones df
# measured. (A dash, by contrast, makes the arithmetic itself fatal, which is
# why each guard needs a fixture of this shape as well as one above.)
t_df_out='Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/disk1s5 1000000 700000 0x10 74% /System/Volumes/Data'
assert_fail "disk_stats refuses an available bash arithmetic would coerce" disk_stats

t_df_out='Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/disk1s5 0x10 700000 250000 74% /System/Volumes/Data'
assert_fail "disk_stats refuses a capacity bash arithmetic would coerce" disk_stats

# A zero-capacity filesystem (devfs, an automount placeholder): the percentage
# would divide by it, and no reclaim can be measured against it.
t_df_out='Filesystem 1024-blocks Used Available Capacity Mounted on
devfs 0 0 0 100% /dev'
assert_fail "disk_stats refuses a zero-capacity filesystem" disk_stats

# Available larger than capacity — nonsense, but clamped rather than trusted,
# so the derived "used" can never go negative and print as -4.00 GB.
t_df_out='Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/disk1s5 1000000 0 4000000 0% /System/Volumes/Data'
assert_ok "disk_stats accepts an over-large available" disk_stats
disk_stats
assert_eq "1000000|0|1000000" "$(t_trio)" "available is clamped to capacity, used never negative"

# ---- total_kb(): the scan's headline ---------------------------------------
#
# Every category, selected or not — this is the "max reclaimable" figure, and
# the one number in the status row that does not move as the user toggles rows.
# The fixture leaves the LARGEST row unselected on purpose: a total_kb that
# quietly filtered by CAT_SEL would otherwise still look big enough to pass.
N=3
CAT_KB=(1048576 2097152 524288)
CAT_SEL=(1 0 1)
assert_eq "3670016" "$(total_kb)" "total_kb sums every category"
assert_eq "1572864" "$(selected_kb)" "selected_kb sums only the selected ones"
CAT_SEL=(0 0 0)
assert_eq "3670016" "$(total_kb)" "total_kb is unchanged by the selection"
assert_eq "0" "$(selected_kb)" "selected_kb with nothing selected"
N=0
assert_eq "0" "$(total_kb)" "total_kb with no categories"

# ---- build_status_line(): the menu's status row ----------------------------
#
# Widths of the three tiers with this fixture: 79 columns with the disk figures,
# 45 without them, 34 with neither. Each boundary is asserted from both sides.
N=2
CAT_KB=(3145728 1048576)
CAT_SEL=(1 0)
DISK_TOTAL_KB=209715200; DISK_USED_KB=157286400; DISK_FREE_KB=52428800

t_full="Selected 1/2   Reclaimable 3.00 GB of 4.00 GB   Disk 50.00 GB free of 200.00 GB"
t_mid="Selected 1/2   Reclaimable 3.00 GB of 4.00 GB"
t_min="Selected 1/2   Reclaimable 3.00 GB"

build_status_line 120; assert_eq "$t_full" "$_SP" "a wide window shows selection, max and disk"
build_status_line 79;  assert_eq "$t_full" "$_SP" "the disk figures fit at exactly their width"
build_status_line 78;  assert_eq "$t_mid"  "$_SP" "one column short, the disk figures go first"
build_status_line 45;  assert_eq "$t_mid"  "$_SP" "the max fits at exactly its width"
build_status_line 44;  assert_eq "$t_min"  "$_SP" "one column short, the max goes too"
build_status_line 20;  assert_eq "$t_min"  "$_SP" "the selection and its size are the floor"

# The width bound is the point of all of the above: this row is one line of a
# fixed-height frame, and a row that wraps scrolls the whole frame on every
# repaint. Swept rather than spot-checked, because a tier boundary is exactly
# where an off-by-one lives.
t_over=""
t_c=34
while [ "$t_c" -le 120 ]; do
    build_status_line "$t_c"
    dwidth "$_SP"
    [ "$_DW" -gt "$t_c" ] && t_over="$t_over $t_c"
    t_c=$((t_c + 1))
done
assert_eq "" "$t_over" "no width from 34 to 120 produces a row wider than the window"

# Lockstep: _SP is what gets measured, _SS is what gets printed, and they must
# describe the same row. Checked at every tier, since a segment can be added to
# one and not the other in any single branch.
build_status_line 120; assert_eq "$_SP" "$(t_strip "$_SS")" "styled and plain agree — wide"
build_status_line 78;  assert_eq "$_SP" "$(t_strip "$_SS")" "styled and plain agree — no disk"
build_status_line 44;  assert_eq "$_SP" "$(t_strip "$_SS")" "styled and plain agree — floor"

# No measurement, no disk segment — at any width. The row simply loses it,
# rather than printing "Disk 0 KB free of 0 KB".
DISK_TOTAL_KB=0; DISK_USED_KB=0; DISK_FREE_KB=0
build_status_line 200
assert_eq "$t_mid" "$_SP" "an unmeasured disk drops the segment instead of printing zeros"

test_summary
