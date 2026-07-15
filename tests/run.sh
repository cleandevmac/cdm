#!/bin/bash
# tests/run.sh — run every tests/test_*.sh and report.
#
#   ./tests/run.sh              # all
#   ./tests/run.sh safe_target  # only files whose name matches
#
# No framework and no dependencies, on purpose: cdm's whole pitch is that it
# runs from a curl pipe with nothing installed, and a test suite that needed
# bats to answer "does this still work on a stock Mac" would be testing a
# machine no user has. Each test file runs in its own bash process so that
# cdm's `set -u`, its EXIT trap, and its top-level globals cannot leak between
# files.
#
# Runs under /bin/bash (3.2) when invoked as ./tests/run.sh, which is the point:
# 3.2 is cdm's floor, and it is the one bash that will reject `declare -A`.

set -u

cd "$(dirname "$0")/.." || exit 1

filter="${1:-}"
pass=0
fail=0
failed_files=""

for t in tests/test_*.sh; do
    [ -e "$t" ] || { echo "no test files found" >&2; exit 1; }
    case "$t" in *"$filter"*) ;; *) continue ;; esac
    if /bin/bash "$t"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        failed_files="$failed_files $t"
    fi
done

echo
if [ "$fail" -gt 0 ]; then
    printf 'FAILED: %d file(s) —%s\n' "$fail" "$failed_files"
    exit 1
fi
printf 'ok: %d file(s)\n' "$pass"
