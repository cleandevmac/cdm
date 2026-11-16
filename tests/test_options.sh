#!/bin/bash
# Option parsing (cdm) — which runs scan code repos.
#
# Interactive runs always scan them; under -y only -p adds them, because -y
# never cleans a project row (flush_project_category gives each default 0) and
# scanning $HOME there would only cost time. see docs/DESIGN.md#project-scanning
#
# lib.sh sources cdm with no arguments. The -y cases source it again in a ( )
# subshell: cdm's own EXIT trap fires when that subshell ends and removes the
# SCAN_DIR it made there, which is asserted too — a leak would strand a
# cdm.XXXXXX in the real $TMPDIR on every run of the suite.

. "$(dirname "$0")/lib.sh"

assert_eq 1 "$PROJECTS_ENABLED" 'no arguments: code repos are scanned'

# t_source <args...> — source cdm with <args>; print PROJECTS_ENABLED and the
# subshell's SCAN_DIR. Through a file: cdm's EXIT trap prints a show-cursor
# escape on the way out, after anything the subshell echoes.
t_source() {
    : > "$HOME/opt.out"
    ( set -- "$@"; CDM_LIB=1 . "$CDM_BIN"
      printf '%s %s\n' "$PROJECTS_ENABLED" "$SCAN_DIR" > "$HOME/opt.out" ) >/dev/null 2>&1
    cat "$HOME/opt.out"
}

out=$(t_source -y)
assert_eq 0 "${out%% *}" '-y: code repos are not scanned'
assert_fail '-y: the subshell removed its SCAN_DIR' test -e "${out#* }"
case "${out#* }" in */cdm.??????) r=ok ;; *) r="no SCAN_DIR: $out" ;; esac
assert_eq ok "$r" '-y: the subshell made a SCAN_DIR (premise for the row above)'

out=$(t_source -y -p)
assert_eq 1 "${out%% *}" '-y -p: code repos are scanned'
assert_fail '-y -p: the subshell removed its SCAN_DIR' test -e "${out#* }"

out=$(t_source -p)
assert_eq 1 "${out%% *}" '-p alone is still accepted'

test_summary
