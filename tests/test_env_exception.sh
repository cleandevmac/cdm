#!/bin/bash
# .env* files are NEVER offered for deletion by the project scan.
#
# The git-ignored pass (git ls-files --others --ignored) surfaces exactly the
# files a repo keeps out of version control — which is almost always where the
# secrets live: .env, .env.local, .env.production, .envrc. Those are precisely
# the files nothing regenerates, so scan_projects skips any git-ignored entry
# whose basename starts with .env (see docs/DESIGN.md#env-file-exception). This
# drives scan_projects end-to-end against a real git repo so it exercises the
# actual `git ls-files` output, not a reimplementation of it.
#
# The negative alone (".env absent") would pass a scan that found NOTHING, which
# is the exact way this could rot into false coverage. So the test also pins the
# positive: a non-.env git-ignored file (secret.conf, debug.log) MUST be offered.
# That proves the git-ignored pass really ran and really produced entries, which
# is what makes the .env* absence meaningful.

. "$(dirname "$0")/lib.sh"

# The gitignore pass fundamentally needs a git binary; every other project-scan
# test avoids it on purpose. On the macOS runner git always ships, but degrade
# to a clean skip rather than a spurious failure if it is somehow absent.
if ! command -v git >/dev/null 2>&1; then
    printf '%-28s  skipped (no git)\n' "$T_FILE"
    exit 0
fi

# --- a real repo whose .gitignore hides both secrets and ordinary junk -------
repo="$HOME/proj"
mkdir -p "$repo"
( cd "$repo" && git init -q ) || { printf '%s: git init failed\n' "$T_FILE" >&2; exit 1; }
cat > "$repo/.gitignore" <<'EOF'
.env
.env.*
.envrc
*.log
secret.conf
EOF
# Secrets/local config (must be spared) ...
: > "$repo/.env"
: > "$repo/.env.local"
: > "$repo/.env.production"
: > "$repo/.envrc"
# ... and ordinary git-ignored junk that SHOULD be offered (proves the scan ran).
: > "$repo/debug.log"
: > "$repo/secret.conf"

# scan_projects reads its config from these (normally filled by load_patterns).
# GI_ON=1 turns on the git-ignored pass; PROJ_N=0 means no name-matched dirs, so
# every offered item comes from git ls-files — the code path under test.
PROJECTS_ENABLED=1
GI_ON=1
GI_METHOD="trash"
PROJ_N=0
PROJ_DIRS=()
PROJ_METHOD=()
SCAN_ROOTS=("$HOME")
SCAN_DEPTH=6
SCAN_MAXREPOS=400
SCAN_PRUNE=()
SCAN_GROUPS=()

# Fresh category arrays, then scan.
CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=(); CAT_PROCS=()
N=0
scan_projects

# Every path the scan is willing to delete, one per line. CAT_PATHS entries are
# themselves newline-separated lists, so this flattens to one path per line.
paths=$(printf '%s\n' "${CAT_PATHS[@]+"${CAT_PATHS[@]}"}" | grep -v '^$')

# offered <path> — is this exact path in the scan's delete set?
offered() { printf '%s\n' "$paths" | grep -qxF "$1"; }

# --- the guarantee ----------------------------------------------------------
# No path whose basename starts with .env is ever offered. The pattern matches
# /.env, /.env.local, /.env.production and /.envrc alike.
assert_eq 0 "$(printf '%s\n' "$paths" | grep -cE '/\.env[^/]*$')" \
    'no .env* file is ever offered for deletion'

# --- proof the scan actually produced git-ignored entries -------------------
# Without these the assertion above could pass on an empty scan and prove nothing.
assert_ok 'ordinary git-ignored junk (debug.log) IS offered — proves the scan ran' \
    offered "$repo/debug.log"
assert_ok 'ordinary git-ignored junk (secret.conf) IS offered' \
    offered "$repo/secret.conf"

test_summary
