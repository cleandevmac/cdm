# tests/lib.sh — sandbox + assertions for the cdm unit tests.
#
# Sourcing this loads every cdm function into the caller's shell via the CDM_LIB
# hook (cdm:1658), with $HOME pointed at a throwaway directory. Three details of
# cdm's top level dictate the order below, and getting any of them wrong makes
# the tests silently assert against the wrong thing rather than fail loudly.
#
#   * $HOME must be exported BEFORE the source. cdm captures HOME_P — the
#     symlink-resolved home — at source time (cdm:277), and is_safe_target
#     compares against that snapshot. Exporting HOME afterwards leaves HOME_P
#     pointing at the real home, and every containment assertion would be
#     testing the developer's actual $HOME instead of the sandbox.
#   * `set --` must come BEFORE the source. cdm parses "$@" at its top level
#     (cdm:112) and a sourced script inherits the caller's positional
#     parameters, so `bash tests/test_foo.sh --verbose` would reach cdm's
#     option parser and exit 1 on "Unknown option" before a single test ran.
#   * Sourcing has side effects on disk: it mkdir -p's $HOME/.cleandevmac
#     (cdm:165) and mktemp -d's SCAN_DIR (cdm:169). The sandbox contains the
#     first; cdm's own EXIT trap removes the second, which is why the cleanup
#     below calls cleanup_on_exit rather than replacing it.
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
        # Silenced because cleanup_on_exit -> leave_tui unconditionally prints
        # the show-cursor escape (cdm:188), which would otherwise spray
        # \033[?25h into the suite's report. The rm -rf of SCAN_DIR is the part
        # we actually want.
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
#     (cdm:127-134), or under tests/mutate.sh a mutant that dies at source time.
#     Arming afterwards leaves a window in which the sandbox leaks, which is not
#     hypothetical: it stranded a pile of cdm-test-home.* dirs in $TMPDIR before
#     this was moved up.
#   * again after, because cdm installs its own `trap cleanup_on_exit EXIT` at
#     source time (cdm:196), silently replacing this one.
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

# Every test file ends with this; its exit status is what run.sh counts.
test_summary() {
    if [ "$T_FAIL" -gt 0 ]; then
        printf '%-28s %2d passed, %2d FAILED\n' "$T_FILE" "$T_PASS" "$T_FAIL"
        exit 1
    fi
    printf '%-28s %2d passed\n' "$T_FILE" "$T_PASS"
    exit 0
}
