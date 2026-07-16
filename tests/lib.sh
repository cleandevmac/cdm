# tests/lib.sh — sandbox + assertions for the cdm unit tests.
#
# Sourcing this loads every cdm function into the caller's shell via the CDM_LIB
# hook near the bottom of cdm, with $HOME pointed at a throwaway directory.
# Three details of cdm's top level dictate the order below, and getting any of
# them wrong makes the tests silently assert against the wrong thing rather than
# fail loudly.
#
#   * $HOME must be exported BEFORE the source. cdm captures HOME_P — the
#     symlink-resolved home — at source time, and is_safe_target compares
#     against that snapshot. Exporting HOME afterwards leaves HOME_P pointing at
#     the real home, and every containment assertion would be testing the
#     developer's actual $HOME instead of the sandbox.
#   * `set --` must come BEFORE the source. cdm parses "$@" at its top level and
#     a sourced script inherits the caller's positional parameters, so
#     `bash tests/test_foo.sh --verbose` would reach cdm's option parser and
#     exit 1 on "Unknown option" before a single test ran.
#   * Sourcing has side effects on disk: it mkdir -p's LOG_DIR
#     ($HOME/.cleandevmac) and mktemp -d's SCAN_DIR, both at cdm's top level.
#     The sandbox contains the first; cdm's own EXIT trap removes the second,
#     which is why the cleanup below calls cleanup_on_exit rather than replacing
#     it.
#
# Note $HOME and HOME_P deliberately differ here: mktemp -d returns a path under
# /var (or /tmp), both of which are symlinks on macOS, so HOME_P resolves to
# /private/... . That asymmetry is real — it is what the physical-containment
# check in is_safe_target exists to handle — so the sandbox reproduces it rather
# than hiding it.

CDM_TESTS_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
CDM_ROOT=$(cd -P "$CDM_TESTS_DIR/.." && pwd -P)
# Overridable so the suite can be pointed at a mutated copy of the script, which
# is how the tests get tested. See tests/mutate.sh.
CDM_BIN="${CDM_BIN:-$CDM_ROOT/cdm}"

T_FILE=$(basename "${0:-tests}")

if [ ! -r "$CDM_BIN" ]; then
    printf '%s: cannot read cdm at %s\n' "$T_FILE" "$CDM_BIN" >&2
    exit 1
fi

TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/cdm-test-home.XXXXXX") || exit 1
export HOME="$TEST_HOME"

_cdm_test_cleanup() {
    # Guarded because this trap is armed BEFORE cdm is sourced (see below), so on
    # an early exit the function does not exist yet.
    if type cleanup_on_exit >/dev/null 2>&1; then
        # Silenced because cleanup_on_exit -> leave_tui() unconditionally
        # prints the show-cursor escape, which would otherwise spray \033[?25h
        # into the suite's report. The rm -rf of SCAN_DIR is the part we
        # actually want.
        cleanup_on_exit >/dev/null 2>&1
    fi
    # Belt and braces on an rm -rf: only ever remove a path this file minted.
    case "${TEST_HOME:-}" in
        */cdm-test-home.??????) rm -rf "$TEST_HOME" 2>/dev/null ;;
    esac
    return 0
}

# Armed BEFORE the source, and again after. Both halves are load-bearing:
#
#   * before, because sourcing cdm can itself exit — a precondition failure
#     (cdm's Darwin and $HOME guards), or under tests/mutate.sh a mutant that
#     dies at source time. Arming afterwards leaves a window in which the
#     sandbox leaks, which is not hypothetical: it stranded a pile of
#     cdm-test-home.* dirs in $TMPDIR before this was moved up.
#   * again after, because cdm installs its own `trap cleanup_on_exit EXIT` at
#     source time, silently replacing this one.
trap _cdm_test_cleanup EXIT

set --
# shellcheck disable=SC1090
CDM_LIB=1 . "$CDM_BIN"

trap _cdm_test_cleanup EXIT

T_PASS=0
T_FAIL=0

# assert_eq <want> <got> <desc>
assert_eq() {
    if [ "$1" = "$2" ]; then
        T_PASS=$((T_PASS + 1))
    else
        T_FAIL=$((T_FAIL + 1))
        printf '  FAIL %s\n       want: [%s]\n       got:  [%s]\n' "$3" "$1" "$2"
    fi
}

# assert_ok <desc> <cmd...> — <cmd> must exit 0.
assert_ok() {
    local desc="$1" rc
    shift
    "$@" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        T_PASS=$((T_PASS + 1))
    else
        T_FAIL=$((T_FAIL + 1))
        printf '  FAIL %s\n       expected exit 0, got %d\n' "$desc" "$rc"
    fi
}

# assert_fail <desc> <cmd...> — <cmd> must exit non-zero.
assert_fail() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        T_FAIL=$((T_FAIL + 1))
        printf '  FAIL %s\n       expected non-zero exit, got 0\n' "$desc"
    else
        T_PASS=$((T_PASS + 1))
    fi
}

# in_locale <locale> <cmd...> — run <cmd> under a locale this suite names, rather
# than whichever one the developer's shell happens to export. Two locale-sensitive
# bugs have shipped in cdm (a collation-resolved bracket range in is_ascii, a
# comma decimal separator out of human_kb's awk), and both hid the same way: the
# suite only ever ran under one locale. An assertion about locale-dependent
# behavior has to pin its own.
#
# Three details, each of which silently makes this pass for free if you get it
# wrong — and "passes for free" is the whole failure mode being defended against:
#
#   * EXPORT, not a bare assignment. A bare `LC_ALL=de_DE.UTF-8` re-runs setlocale
#     in THIS shell, which is enough for a bash builtin or a pattern match, but it
#     is not in the environment — so a command that forks (awk, sort, du) never
#     sees it and answers in the developer's locale. Against unfixed code that
#     reads as a pass.
#   * ASSIGNMENT, not the `LC_ALL=x cmd` prefix form. bash 3.2 re-runs setlocale
#     when the variable is assigned, but not for the temporary environment of a
#     FUNCTION call, so the prefix form leaves this shell's own locale untouched —
#     which is what a caller testing bash-internal behavior (is_ascii) needs.
#   * the ( ) subshell, so the export cannot leak into every later assertion in
#     the file: assert_ok runs its command in the CURRENT shell.
#
# The pair is what makes one helper serve both callers: the export reaches forked
# children, and assigning it (rather than prefixing) still re-inits this shell.
in_locale() { ( export LC_ALL="$1"; shift; "$@" ); }

# Every test file ends with this; its exit status is what run.sh counts.
test_summary() {
    if [ "$T_FAIL" -gt 0 ]; then
        printf '%-28s %2d passed, %2d FAILED\n' "$T_FILE" "$T_PASS" "$T_FAIL"
        exit 1
    fi
    printf '%-28s %2d passed\n' "$T_FILE" "$T_PASS"
    exit 0
}
