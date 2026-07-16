#!/bin/bash
# The "Small helpers" section of cdm, minus is_safe_target — that one ends the
# section and has tests/test_safe_target.sh to itself. The eight left over are
# the ones the rest of the script leans on: small enough to read as
# self-evidently correct, and each turning on a single boundary, a unit, or a
# shell default that only misbehaves at exactly one input.
#
# What the assertions below are shaped around:
#
#   * human_kb formats in awk, so its result is a STRING, not a number, and each
#     branch rounds to its own width: "%.0f MB" keeps no fraction at all, so
#     1048575 KB prints a bare "1024 MB" one KB below the GB threshold, and the
#     tool shows "1024 MB" and "1.00 GB" for two sizes one KB apart. An
#     assertion phrased as "about a gigabyte" would pass against either format
#     AND against a swapped threshold, so every expectation here is the exact
#     byte string a user reads off the menu.
#   * human_to_kb is decimal where Docker is decimal (kB = 1000) and binary
#     where Docker is binary (KiB = 1024). That is deliberate, and the two are
#     only 2.4% apart — far too close for a wrong multiplier to ever look wrong
#     in the TUI. Both families are pinned against the same magnitude so a
#     multiplier copied between the two rows cannot survive.
#   * du_kb's -k is as load-bearing as its arithmetic, and a one-sided "is the
#     size big enough" assertion cannot see it: `du` defaults to 512-byte blocks
#     on macOS, so dropping -k still returns a plausible integer, just doubled.
#     Its result is bounded on both sides for that reason.
#   * engine_ok is the command-INJECTION guard, not a typo check: engine names
#     arrive from a rules JSON file and reach a shell command. The load-bearing
#     assertions are therefore the refusals, and they have to be the shapes an
#     attacker would actually write, not just misspellings.
#   * is_nonempty tests `-e OR -L` and globs `.[!.]*` next to `*`. Both look
#     redundant; neither is. A dangling symlink fails -e, and a directory
#     holding only dotfiles is invisible to `*`. Each gets a fixture that
#     ISOLATES it — the dotfile dir holds only a dotfile, the dangling-link dir
#     holds only the dangling link — so no other entry in the loop can carry the
#     pass and hide a broken clause.
#   * cat_indices reads the global N, so N is set explicitly at each assertion.
#     Inheriting whatever cdm's top level left there would make the loop bound
#     untestable.
#   * bounded backgrounds two processes and its failure mode is a hang, not a
#     wrong answer. It is checked on the clock as well as on the status.

. "$(dirname "$0")/lib.sh"

# ---- local helpers ---------------------------------------------------------
#
# t_-prefixed so they cannot collide with anything cdm sourced into this shell.
# assert_ok/assert_fail only see a command's exit status, so these turn the
# things worth pinning exactly — an exit status, a wall clock — into stdout that
# assert_eq can compare.

t_rc() { "$@"; echo $?; }
t_is_int() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# ---- human_kb(): KB / MB / GB thresholds -----------------------------------
#
# Every boundary is asserted from both sides. The KB branch is plain `echo`, so
# it is the only one that echoes its input back verbatim.

assert_eq "0 KB"     "$(human_kb 0)"        "human_kb 0"
assert_eq "1 KB"     "$(human_kb 1)"        "human_kb 1"
assert_eq "1023 KB"  "$(human_kb 1023)"     "human_kb 1023 — last KB"
assert_eq "1 MB"     "$(human_kb 1024)"     "human_kb 1024 — first MB"

# The MB/GB seam, and the reason "%.0f MB" is worth pinning: 1048575/1024 is
# 1023.999, which the MB branch ROUNDS UP to a bare "1024 MB" — the tool prints
# 1024 MB and 1.00 GB for two sizes one KB apart, and that is correct.
assert_eq "1024 MB"  "$(human_kb 1048575)"  "human_kb 1048575 — last MB, rounded up"
assert_eq "1.00 GB"  "$(human_kb 1048576)"  "human_kb 1048576 — first GB"

# %.2f, not %.0f: the GB branch is the one place a fraction is kept.
assert_eq "1.50 GB"  "$(human_kb 1572864)"  "human_kb keeps 2 decimals in GB"

# Missing/empty argument defaults to 0 rather than erroring under `set -u`.
assert_eq "0 KB"     "$(human_kb)"          "human_kb with no argument"
assert_eq "0 KB"     "$(human_kb "")"       "human_kb with an empty argument"

# ---- human_to_kb(): Docker-style sizes -------------------------------------
#
# Result is whole KiB, truncated by awk's %d (never rounded).

assert_eq "0"          "$(human_to_kb 0B)"     "human_to_kb 0B"
assert_eq "488"        "$(human_to_kb 500kB)"  "human_to_kb 500kB — 500000/1024, truncated"
assert_eq "781250"     "$(human_to_kb 800MB)"  "human_to_kb 800MB"
assert_eq "1757812"    "$(human_to_kb 1.8GB)"  "human_to_kb 1.8GB — fractional input"
assert_eq "976562500"  "$(human_to_kb 1TB)"    "human_to_kb 1TB"

# %d TRUNCATES; it does not round. Most sizes cannot show the difference —
# 500000/1024 is 488.28 and 1.8e9/1024 lands exactly on .5, which awk's %.0f
# resolves to even and so agrees with %d by coincidence. 700kB is 683.59, where
# truncation (683) and rounding (684) finally disagree. Without this row, %d
# could become %.0f unnoticed.
assert_eq "683"        "$(human_to_kb 700kB)"  "human_to_kb truncates 683.59 rather than rounding"

# A bare number with no unit is 1 KiB per 1024 — this is the `""` arm of the
# unit case, and it is the only arm reachable with no letters in the input at
# all, so nothing else covers it.
assert_eq "2"          "$(human_to_kb 2048)"   "human_to_kb of a unitless number"

# Binary units. These are the same magnitudes as the decimal rows above, so a
# multiplier copied from the wrong column shows up as a diff rather than as a
# number that merely looks big enough.
assert_eq "2097152"    "$(human_to_kb 2GiB)"   "human_to_kb 2GiB — binary, 2*1073741824/1024"
assert_eq "1073741824" "$(human_to_kb 1TiB)"   "human_to_kb 1TiB — binary"

# The decimal-vs-binary distinction itself, stated as the gap it creates. Docker
# reports both spellings and means different numbers by them; collapsing the two
# would misreport every container size by 2.4%.
assert_eq "976562"     "$(human_to_kb 1GB)"    "human_to_kb 1GB — decimal, 1e9/1024"
assert_eq "1048576"    "$(human_to_kb 1GiB)"   "human_to_kb 1GiB — binary, and NOT 1GB"

# Garbage yields 0 — the scan must not inflate a total from a size it could not
# read. Each of these takes a different route to 0:
#   ""       -> ${1:-0} substitutes "0", so the unit is empty and mult=1.
#   "abc"    -> the number prefix is empty, caught by human_to_kb's '' guard.
#   "12XB"   -> the number parses, the unit falls through to the `*)` arm.
#   "1.2.3GB"-> "1.2.3" passes the *[!0-9.]* guard (it IS only digits and dots)
#               and reaches awk, where `1.2 .3` is an implicit CONCATENATION,
#               not a syntax error: awk builds "1.2300000000", divides by 1024,
#               and %d truncates 0.0012 to 0. The right answer by luck rather
#               than by the guard — asserted so a change to either the guard or
#               the awk expression has to confront it.
assert_eq "0" "$(human_to_kb "")"        "human_to_kb empty string"
assert_eq "0" "$(human_to_kb abc)"       "human_to_kb non-numeric"
assert_eq "0" "$(human_to_kb 12XB)"      "human_to_kb unknown unit"
assert_eq "0" "$(human_to_kb 1.2.3GB)"   "human_to_kb malformed number"

# ---- expand_tilde() --------------------------------------------------------

assert_eq "$HOME/x" "$(expand_tilde "~/x")" "expand_tilde ~/x"
assert_eq "$HOME"   "$(expand_tilde "~")"   "expand_tilde bare ~"

# Only "~/" and a bare "~" expand. "~user" is left ALONE — bash's own ~user
# expansion resolves another account's home, and cdm has no business deleting
# out of one; is_safe_target would refuse it anyway, but the string never gets
# that far.
assert_eq "~user"      "$(expand_tilde "~user")"      "expand_tilde does NOT expand ~user"
assert_eq "~user/junk" "$(expand_tilde "~user/junk")" "expand_tilde does NOT expand ~user/junk"

# Everything else is returned verbatim.
assert_eq "/abs"        "$(expand_tilde "/abs")"        "expand_tilde leaves an absolute path"
assert_eq "relative"    "$(expand_tilde "relative")"    "expand_tilde leaves a relative path"
assert_eq "/x/~/y"      "$(expand_tilde "/x/~/y")"      "expand_tilde only matches a LEADING ~"

# Spaces survive: real patterns are full of them
# (~/Library/Application Support/*/Code Cache).
assert_eq "$HOME/Library/Application Support/Code" \
    "$(expand_tilde "~/Library/Application Support/Code")" \
    "expand_tilde preserves spaces"

# ---- engine_ok(): the injection whitelist ----------------------------------

assert_ok "docker is a known engine"  engine_ok docker
assert_ok "podman is a known engine"  engine_ok podman
assert_ok "nerdctl is a known engine" engine_ok nerdctl

# The refusals. These are the point of the function: the value comes from JSON
# and lands in a shell command, so anything that is not EXACTLY one of the three
# names above has to be turned away — not sanitized, not prefix-matched.
assert_fail "an unrelated command"          engine_ok rm
assert_fail "a shell metacharacter payload" engine_ok "docker; rm -rf /"
assert_fail "a command-substitution payload" engine_ok 'docker$(rm -rf /)'
assert_fail "an argument smuggled along"    engine_ok "docker rm"
assert_fail "the empty string"              engine_ok ""
assert_fail "wrong case"                    engine_ok DOCKER
assert_fail "a prefix of a known engine"    engine_ok dockerx
assert_fail "leading whitespace"            engine_ok "  docker"
assert_fail "trailing whitespace"           engine_ok "docker "
# A glob is data here, never a pattern — engine_ok globbing its own input would
# make "*" match every arm of the case.
assert_fail "a glob"                        engine_ok "*"

# ---- is_nonempty() ---------------------------------------------------------

mkdir -p "$HOME/ne" || exit 1

# A regular file is nonempty by definition — even a zero-byte one. cdm cares
# whether a path is worth reporting, not how many bytes are in it, and the check
# is `-f`, not `-s`.
: > "$HOME/ne/empty-file"
printf 'x' > "$HOME/ne/full-file"
assert_ok "a regular file with content" is_nonempty "$HOME/ne/full-file"
assert_ok "an empty regular file is still a file" is_nonempty "$HOME/ne/empty-file"

# An empty directory. Neither glob matches, so both stay literal and the -e/-L
# tests fail on the unexpanded pattern itself. This also pins the `!` in
# .[!.]* : a glob of .* would match "." and ".." and report every empty
# directory on the machine as full.
mkdir -p "$HOME/ne/empty-dir" || exit 1
assert_fail "an empty directory" is_nonempty "$HOME/ne/empty-dir"

mkdir -p "$HOME/ne/has-file" || exit 1
: > "$HOME/ne/has-file/thing"
assert_ok "a directory holding a regular file" is_nonempty "$HOME/ne/has-file"

# ONLY a dotfile: invisible to "$1"/*, which is exactly why the loop also globs
# "$1"/.[!.]* . Nothing else lives in this dir, so if that second glob goes away
# the assertion has nothing to fall back on. (Caches like ~/.cache/x/.lock are
# real; reporting such a dir as empty would silently drop it from the scan.)
mkdir -p "$HOME/ne/dot-only" || exit 1
: > "$HOME/ne/dot-only/.hidden"
assert_ok "a directory holding only a dotfile" is_nonempty "$HOME/ne/dot-only"

# ONLY a dangling symlink: -e is FALSE for it (the target does not exist), so
# this reaches the `|| [ -L "$__e" ]` clause and nothing else. Dangling links
# are the normal state of a stale cache dir, and they still occupy a directory
# entry that a clean should remove.
mkdir -p "$HOME/ne/dangling" || exit 1
ln -s "$HOME/ne/no-such-target" "$HOME/ne/dangling/link"
assert_fail "the fixture link really is dangling" test -e "$HOME/ne/dangling/link"
assert_ok "the fixture link really is a symlink"  test -L "$HOME/ne/dangling/link"
assert_ok "a directory holding only a dangling symlink" is_nonempty "$HOME/ne/dangling"

assert_fail "a nonexistent path" is_nonempty "$HOME/ne/no-such-thing"
assert_fail "a nonexistent path under a nonexistent dir" \
    is_nonempty "$HOME/ne/no-such-dir/no-such-thing"

# ---- du_kb() ---------------------------------------------------------------
#
# A missing path is 0, not empty: the caller sums this into CAT_KB with $((...)),
# where an empty string is a syntax error rather than a zero.
assert_eq "0" "$(du_kb "$HOME/no-such-path-xyzzy")" "du_kb of a nonexistent path"

# Real bytes, not zeros — a hole or a compressible run could make `du` report
# fewer blocks than were written, and the point here is only that a real size
# comes back as a bare integer.
mkdir -p "$HOME/du" || exit 1
dd if=/dev/urandom of="$HOME/du/blob" bs=1024 count=512 2>/dev/null || exit 1
assert_ok "du_kb of a real file is a bare integer" t_is_int "$(du_kb "$HOME/du/blob")"

# Bounded on BOTH sides, and the upper bound is the load-bearing one: it is what
# pins the -k. `du` defaults to 512-byte blocks on macOS, so dropping -k would
# still return a plausible integer — 1024 for this file — and every "is it big
# enough" assertion would sail through while cdm doubled every size it reports.
# The window is wide enough that the exact allocation stays the filesystem's
# business and narrow enough that a unit change cannot fit inside it.
assert_ok "du_kb of a 512K file reports at least 256" \
    test "$(du_kb "$HOME/du/blob")" -ge 256
assert_ok "du_kb reports KB, not 512-byte blocks or bytes" \
    test "$(du_kb "$HOME/du/blob")" -le 768
assert_ok "du_kb of a directory sums its contents" \
    test "$(du_kb "$HOME/du")" -ge 256

# ---- cat_indices() ---------------------------------------------------------
#
# Reads the global N. Set it here rather than inheriting it: at this point cdm's
# category-model declarations have left N=0, which would make the N=0 case pass
# without the function being involved at all.
N=3
assert_eq "0
1
2" "$(cat_indices)" "cat_indices with N=3 yields 0..N-1"

N=1
assert_eq "0" "$(cat_indices)" "cat_indices with N=1"

# Nothing at all — not "0", not a blank line. Every caller loops over this, and
# a stray index would dereference CAT_* past its end.
N=0
assert_eq "" "$(cat_indices)" "cat_indices with N=0 yields nothing"

# ---- bounded() -------------------------------------------------------------
#
# Timeouts are 1s throughout: the suite must not pay for them.

# A command that finishes well inside the timeout reports ITS OWN status, not
# the watcher's. Both a success and a specific failure code, because "returns 0"
# and "returns non-zero" are each half the contract.
assert_eq "0" "$(t_rc bounded 1 true)"             "bounded returns 0 for a fast success"
assert_eq "3" "$(t_rc bounded 1 sh -c 'exit 3')"   "bounded passes a non-zero status through"
assert_eq "1" "$(t_rc bounded 1 false)"            "bounded passes exit 1 through"

# stdout survives the round trip through the background job — this is how the
# container callers actually read `docker system df`.
assert_eq "hello" "$(bounded 1 echo hello)" "bounded does not swallow stdout"

# The timeout itself. One run, two assertions: the WALL CLOCK proves the watcher
# fired (without it, this returns in 10s, not 1), and the status proves the
# caller can tell a killed command from a successful one. `sleep 10` rather than
# something unbounded so that a regression costs the suite 10 seconds instead of
# hanging it forever.
t_start=$SECONDS
bounded 1 sleep 10 >/dev/null 2>&1
t_kill_rc=$?
t_kill_secs=$((SECONDS - t_start))

assert_ok "a command outliving the timeout is killed, not waited on" \
    test "$t_kill_secs" -lt 5
assert_ok "a killed command does not report success" \
    test "$t_kill_rc" -ne 0

# And a fast command must not be made to wait out its own timeout — bounded has
# to reap the watcher, not join it. Timed over five runs rather than one: SECONDS
# has 1s granularity, so a single run straddling a second boundary reads as 1
# either way, and an assertion that cannot distinguish 0 from 1 cannot test this.
# Five runs are ~0s if the watcher is reaped and ~5s if it is waited on.
t_start=$SECONDS
t_i=0
while [ "$t_i" -lt 5 ]; do
    bounded 1 true >/dev/null 2>&1
    t_i=$((t_i + 1))
done
assert_ok "a fast command returns without waiting out its timeout" \
    test "$((SECONDS - t_start))" -lt 3

test_summary
