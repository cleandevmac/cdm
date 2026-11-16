#!/bin/bash
# ACCOUNT_PROBE (cdm) — the login-shell probe account_path runs as each account
# under sudo, with that account's shell as $0. Two properties, each pinned here:
#
#   * it prints the PATH the login shell ends up with, after a CDM_PATH= marker on
#     a line of its own, whatever the dotfiles print around it;
#   * it kills a login shell that is still running after 5 s, itself. The limit has
#     to live inside the probe: sudo gives the probe a pty of its own and relays
#     the terminal's keys to it, so killing only sudo's parent (all `bounded` can
#     reach) would leave sudo running and feeding a hung shell the keys typed at
#     the next prompt. see docs/DESIGN.md#sudo-accounts
#
# The probe needs no root to test: it is a bash -c script, run here as the normal
# user with fake "shells". This file is separate from test_accounts.sh because the
# second property costs a real 5 s wait, which every mutation of that file would
# otherwise pay again.

. "$(dirname "$0")/lib.sh"

P_DIR="$HOME/probe"
mkdir -p "$P_DIR" || exit 1

# A login shell whose dotfiles print around the PATH it sets.
cat > "$P_DIR/chatty-sh" <<'SH'
#!/bin/sh
[ "$1" = -l ] && [ "$2" = -c ] || exit 64
echo "Last login: never"
PATH=/from/profile:$PATH; export PATH
/bin/sh -c "$3"
echo "bye"
SH
# A login shell whose dotfiles hang. It records its pid first, so the test can tell
# whether the probe killed it or merely stopped waiting for it.
cat > "$P_DIR/hung-sh" <<SH
#!/bin/sh
echo \$\$ > "$P_DIR/hung.pid"
exec /bin/sleep 12
SH
chmod +x "$P_DIR/chatty-sh" "$P_DIR/hung-sh"

out=$(env -i PATH=/usr/bin:/bin /bin/bash -c "$ACCOUNT_PROBE" "$P_DIR/chatty-sh" < /dev/null); rc=$?
assert_eq 0 "$rc" 'the probe exits 0'
assert_eq '/from/profile:/usr/bin:/bin' "$(printf '%s\n' "$out" | sed -n 's/^CDM_PATH=//p')" \
    'the probe prints the login PATH after its marker, around the dotfiles chatter'

start=$(date +%s)
out=$(env -i PATH=/usr/bin:/bin /bin/bash -c "$ACCOUNT_PROBE" "$P_DIR/hung-sh" < /dev/null); rc=$?
took=$(( $(date +%s) - start ))
assert_eq 0 "$rc" 'a hung login shell: the probe still exits 0'
[ "$took" -le 8 ] && r=ok || r="took ${took}s"
assert_eq ok "$r" 'a hung login shell: the probe gives up after about 5 s'
assert_eq '' "$(printf '%s\n' "$out" | sed -n 's/^CDM_PATH=//p')" 'a hung login shell: no PATH comes back'
pid=$(cat "$P_DIR/hung.pid" 2>/dev/null)
case "$pid" in ''|*[!0-9]*) r="no pid recorded" ;; *) kill -0 "$pid" 2>/dev/null && r="still running" || r=gone ;; esac
assert_eq gone "$r" 'a hung login shell: the probe killed it, not just stopped waiting'
[ "$r" = "still running" ] && kill -9 "$pid" 2>/dev/null

test_summary
