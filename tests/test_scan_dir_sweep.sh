#!/bin/bash
# sweep_stale_scan_dirs (cdm) — reclaims SCAN_DIRs stranded by killed runs.
#
# cleanup_on_exit handles the normal path, but an EXIT trap cannot run when the
# process is killed outright (SIGKILL, or SIGHUP when the terminal closes), so
# those runs leak an empty cdm.XXXXXX forever. This was not theoretical: 107 of
# them, ~27 MB, were stranded in $TMPDIR before the sweep existed.
#
# This is the only rm in cdm that does not pass is_safe_target — it cannot, as
# $TMPDIR is not under $HOME — so the blast radius is bounded by the glob alone.
# That makes "what it must NOT match" the important half of this file.

. "$(dirname "$0")/lib.sh"

# The function reads ${TMPDIR:-/tmp} at call time, so it can be pointed at a
# sandbox. Everything below happens in here; the real $TMPDIR is never touched.
TMPDIR="$HOME/tmp/"
export TMPDIR
mkdir -p "$TMPDIR" || exit 1

# stale <name> — a dir matching cdm's mktemp template, backdated past the floor.
stale() { mkdir -p "$TMPDIR$1"; touch -t 202001010000 "$TMPDIR$1"; }
fresh() { mkdir -p "$TMPDIR$1"; }

# ---- sweeps what earlier runs stranded -------------------------------------

stale cdm.aaaaaa
stale cdm.ZZ99zz
fresh cdm.newnew          # this run's era — must survive the mtime floor
SCAN_DIR="$TMPDIR/cdm.mineee"; mkdir -p "$SCAN_DIR"
touch -t 202001010000 "$SCAN_DIR"   # old enough to sweep, but it is OURS

# Things the glob must never touch. A sweep that reaches any of these is a bug
# with a much worse blast radius than the litter it was cleaning up.
mkdir -p "$TMPDIR/cdm"                 # no suffix
mkdir -p "$TMPDIR/cdm.abc"             # too short for the ?????? template
mkdir -p "$TMPDIR/cdm.toolongxx"       # too long
mkdir -p "$TMPDIR/notcdm.aaaaaa"       # wrong prefix
mkdir -p "$TMPDIR/cdm-test-home.aaaaa" # a different tool's template
mkdir -p "$TMPDIR/important-data"
: > "$TMPDIR/cdm.file01"               # a FILE matching the glob, not a dir
# Backdate every one of them past the mtime floor, cdm.file01 included. Without
# this they are merely too new to sweep, and each assertion below would pass with
# the guard it is testing deleted — the sweep would look bounded when it is not.
for p in cdm cdm.abc cdm.toolongxx notcdm.aaaaaa cdm-test-home.aaaaa \
         important-data cdm.file01; do
    touch -t 202001010000 "$TMPDIR/$p"
done

sweep_stale_scan_dirs

assert_ok "stale scan dir is swept"        test ! -d "$TMPDIR/cdm.aaaaaa"
assert_ok "second stale scan dir is swept" test ! -d "$TMPDIR/cdm.ZZ99zz"

# The mtime floor is what makes this safe to run while another cdm is scanning.
assert_ok "a recent scan dir is left alone" test -d "$TMPDIR/cdm.newnew"

# Sweeping our own live SCAN_DIR would delete the run's working state.
assert_ok "this run's own SCAN_DIR is left alone" test -d "$SCAN_DIR"

# ---- must not touch anything else ------------------------------------------

assert_ok "bare 'cdm' dir untouched"        test -d "$TMPDIR/cdm"
assert_ok "short suffix untouched"          test -d "$TMPDIR/cdm.abc"
assert_ok "long suffix untouched"           test -d "$TMPDIR/cdm.toolongxx"
assert_ok "wrong prefix untouched"          test -d "$TMPDIR/notcdm.aaaaaa"
assert_ok "another template untouched"      test -d "$TMPDIR/cdm-test-home.aaaaa"
assert_ok "unrelated data untouched"        test -d "$TMPDIR/important-data"
assert_ok "a plain file is not swept"       test -f "$TMPDIR/cdm.file01"

# ---- degenerate cases ------------------------------------------------------

# An empty TMPDIR must not make the glob fall through to the literal pattern.
rm -rf "$TMPDIR"; mkdir -p "$TMPDIR"
assert_ok "no scan dirs at all is not an error" sweep_stale_scan_dirs

# A stale dir with contents still goes: a killed run's scratch is still scratch.
stale cdm.xxxxxx
mkdir -p "$TMPDIR/cdm.xxxxxx/sub"; : > "$TMPDIR/cdm.xxxxxx/sub/size_0"
touch -t 202001010000 "$TMPDIR/cdm.xxxxxx"
sweep_stale_scan_dirs
assert_ok "a non-empty stale scan dir is swept too" test ! -d "$TMPDIR/cdm.xxxxxx"

test_summary
