#!/bin/bash
# Under sudo (cdm) — root cleans nobody's files itself: it runs one ordinary cdm
# per account, as that account's own user, with a clean environment.
# see docs/DESIGN.md#sudo-accounts
#
# Nothing here needs root. dscl, id, launchctl and sudo are shell functions that
# answer from canned data and record each call's argv in a file under the sandbox,
# so the assertions are about exactly what root would have run. The rules are the
# real rules/ (PATTERNS_SRC), so resolve_patterns stages offline.

. "$(dirname "$0")/lib.sh"

# No prompt between accounts: tests never read a key, even from a terminal.
exec 3</dev/null

H="$HOME/homes"
CALLS="$HOME/calls"
mkdir -p "$H" "$CALLS"
for t_n in hoangnc hoangb2b iot spf-dev tham Zed root daemon _hidden nologin falseuser; do
    mkdir -p "$H/$t_n"
done

# ---- shims --------------------------------------------------------------------

FAKE_DSCL=""
dscl() { printf '%s\n' "$FAKE_DSCL"; }

# id -P <name> — a passwd line; an unknown name fails like the real one.
id() {
    [ "$1" = "-P" ] || { command id "$@"; return; }
    case "$2" in
        hoangnc)   echo "hoangnc:********:501:20::0:0:Hoang NC:$H/hoangnc:/bin/zsh" ;;
        hoangb2b)  echo "hoangb2b:********:502:20::0:0:B2B:$H/hoangb2b:/bin/bash" ;;
        iot)       echo "iot:********:503:20::0:0:IoT box:$H/iot:/bin/zsh" ;;
        spf-dev)   echo "spf-dev:********:504:20::0:0:spf dev:$H/spf-dev:/opt/homebrew/bin/fish" ;;
        tham)      echo "tham:********:505:20::0:0:5 Tham:$H/tham:/bin/zsh" ;;
        Zed)       echo "Zed:********:607:20::0:0::$H/Zed:/bin/sh" ;;
        root)      echo "root:********:0:0::0:0:System Administrator:$H/root:/bin/sh" ;;
        daemon)    echo "daemon:********:1:1::0:0:System Services:$H/daemon:/bin/sh" ;;
        _hidden)   echo "_hidden:********:600:20::0:0:Hidden:$H/_hidden:/bin/zsh" ;;
        nologin)   echo "nologin:********:603:20::0:0:No login:$H/nologin:/sbin/nologin" ;;
        falseuser) echo "falseuser:********:604:20::0:0:False:$H/falseuser:/usr/bin/false" ;;
        nohome)    echo "nohome:********:605:20::0:0:No home:$H/missing:/bin/zsh" ;;
        roothome)  echo "roothome:********:606:20::0:0:Slash:/:/bin/zsh" ;;
        relhome)   echo "relhome:********:609:20::0:0:Rel:homes/relhome:/bin/zsh" ;;
        *) return 1 ;;
    esac
}

FAKE_ASUSER=""                # "|uid|" for accounts with a launchd session
launchctl() {
    [ "$1" = "asuser" ] || return 1
    if [ "$3" = "/usr/bin/true" ]; then
        case "$FAKE_ASUSER" in *"|$2|"*) return 0 ;; *) return 1 ;; esac
    fi
    printf '%s\n' "$2 $3" > "$CALLS/asuser.$5"       # asuser <uid> sudo -u <name> …
    shift 2
    "$@"
}

# sudo -u <name> -- <cmd...>: a login-shell probe prints FAKE_PROBE_<name>; a run is
# recorded in run.<name>, what its stdin is in stdin.<name> (tty, null or other),
# and returns FAKE_RC_<name> (default 0).
sudo() {
    [ "$1" = "-u" ] && [ "$3" = "--" ] || return 99
    local name="$2" a probe=0 v
    for a; do [ "$a" = "$ACCOUNT_PROBE" ] && probe=1; done
    v=$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_')
    if [ "$probe" -eq 1 ]; then
        printf '%s\n' "$@" > "$CALLS/probe.$name"
        eval "printf '%s' \"\${FAKE_PROBE_$v:-}\""
        eval "return \${FAKE_PROBE_RC_$v:-0}"
    fi
    printf '%s\n' "$@" > "$CALLS/run.$name"
    if [ -t 0 ]; then echo tty; elif [ /dev/fd/0 -ef /dev/null ]; then echo null; else echo other; fi > "$CALLS/stdin.$name"
    eval "return \${FAKE_RC_$v:-0}"
}

t_clear() { rm -f "$CALLS"/* 2>/dev/null; }

# ---- account_rows ---------------------------------------------------------------

FAKE_DSCL="_spotlight                 89
root                       0
daemon                     1
nobody                     -2
hoangnc                    501
tham                       505
iot                        503
spf-dev                    504
hoangb2b                   502
Zed                        607
_hidden                    600
-evil                      601
bad\$name                   602
nologin                    603
falseuser                  604
nohome                     605
roothome                   606
đức                        608
relhome                    609"

t_names() { account_rows | cut -d "$US" -f 1 | paste -sd ' ' -; }

SUDO_USER=tham
assert_eq "tham Zed hoangb2b hoangnc iot spf-dev" "$(t_names)" \
    "account_rows: uid >= 501, real names, a login shell and a home; the invoker first, then C order"
SUDO_USER=hoangnc
assert_eq "hoangnc Zed hoangb2b iot spf-dev tham" "$(t_names)" "account_rows: whoever ran sudo comes first"
SUDO_USER=""
assert_eq "Zed hoangb2b hoangnc iot spf-dev tham" "$(t_names)" "account_rows: no SUDO_USER, C order only"

SUDO_USER=tham
assert_eq "tham${US}505${US}$H/tham${US}/bin/zsh" "$(account_rows | sed -n 1p)" \
    "account_rows: name, uid, home and shell; a gecos with spaces parses"
assert_eq "Zed${US}607${US}$H/Zed${US}/bin/sh" "$(account_rows | sed -n 2p)" "account_rows: an empty gecos parses"

# ---- ONLY_USERS: pick_accounts ----------------------------------------------------

t_rows=$(account_rows)
ONLY_USERS="nosuch$NL"
t_err=$(pick_accounts "$t_rows" 2>&1 >/dev/null); t_rc=$?
assert_eq 1 "$t_rc" "--user with an unknown name fails"
assert_eq "No account named nosuch on this Mac. Accounts: tham, Zed, hoangb2b, hoangnc, iot, spf-dev" \
    "$(printf '%s' "$t_err" | sed "s/$(printf '\033')\[[0-9;]*m//g")" "...and names the accounts there are"
ONLY_USERS="iot${NL}hoangnc$NL"
assert_eq "hoangnc iot" "$(pick_accounts "$t_rows" | cut -d "$US" -f 1 | paste -sd ' ' -)" \
    "--user keeps the dispatcher's order, not the order typed"
ONLY_USERS="ham$NL"
assert_fail "--user matches whole names only" pick_accounts "$t_rows"
ONLY_USERS=""

# ---- account_path -----------------------------------------------------------------

t_defaults() { # <home>
    printf '%s' "$1/.local/bin:$1/.cargo/bin:$1/.docker/bin:$1/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}
FAKE_PROBE_tham="Last login: today
CDM_PATH=/old/bin
motd: hello

CDM_PATH=/a/bin:rel/bin::/usr/bin:/a/bin:./x:/b
trailer"
t_clear
assert_eq "/a/bin:/usr/bin:/b:$H/tham/.local/bin:$H/tham/.cargo/bin:$H/tham/.docker/bin:$H/tham/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/bin:/usr/sbin:/sbin" \
    "$(account_path 505 tham "$H/tham" /bin/zsh)" \
    "account_path: the last marker's entries first, relative and repeated ones dropped, then the defaults"
assert_eq "-u
tham
--
/usr/bin/env
-i
HOME=$H/tham
USER=tham
LOGNAME=tham
SHELL=/bin/zsh
PATH=/usr/bin:/bin:/usr/sbin:/sbin
TERM=dumb
/bin/bash
-c
$ACCOUNT_PROBE
/bin/zsh" "$(cat "$CALLS/probe.tham" 2>/dev/null)" \
    "account_path: the probe runs the login shell as the account, with a clean environment"
assert_fail "account_path: the probe's file is gone afterwards" test -e "$SCAN_DIR/path.505"

t_clear
assert_eq "$(t_defaults "$H/spf-dev")" "$(account_path 504 spf-dev "$H/spf-dev" /opt/homebrew/bin/fish)" \
    "account_path: a fish shell gets the defaults"
assert_fail "account_path: ...and is never probed" test -e "$CALLS/probe.spf-dev"

FAKE_PROBE_iot="zsh: something broke"; FAKE_PROBE_RC_iot=1
assert_eq "$(t_defaults "$H/iot")" "$(account_path 503 iot "$H/iot" /bin/zsh)" \
    "account_path: a failed probe gets the defaults"
FAKE_PROBE_iot=""; FAKE_PROBE_RC_iot=0

# ---- script_dir_for: no rules next to the staged copy ------------------------------

assert_eq "" "$(script_dir_for "$SCAN_DIR/cdm")" "script_dir_for: a script in \$SCAN_DIR has no rules next to it"
t_scan_p=$(cd -P "$SCAN_DIR" && pwd -P)
mkdir -p "$SCAN_DIR/sub"
assert_eq "" "$(script_dir_for "$t_scan_p/sub/cdm")" "script_dir_for: ...nor below it, by its physical path"
assert_eq "$CDM_ROOT" "$(cd -P "$(script_dir_for "$CDM_ROOT/cdm")" && pwd -P)" "script_dir_for: elsewhere, its own folder"
assert_eq "" "$(script_dir_for cdm)" "script_dir_for: no folder in the path, no folder"

# A file listed in index.json is a name, never a path out of the staging folder.
t_rules="$HOME/evil/rules"; mkdir -p "$t_rules"
cp "$CDM_ROOT/rules/dev-caches.json" "$t_rules/"
echo '{}' > "$HOME/evil/escape.json"
printf '%s\n' '{ "patternFiles": ["dev-caches.json", "../escape.json"], "orphanConfig": "../escape.json" }' > "$t_rules/index.json"
( PATTERNS_SRC="$t_rules"; resolve_patterns ) >/dev/null 2>&1
assert_fail "resolve_patterns: a listed ../ name is not copied out of the staging folder" test -e "$SCAN_DIR/escape.json"
rm -rf "$SCAN_DIR/patterns"

# ---- run_accounts -----------------------------------------------------------------

FAKE_DSCL="hoangnc 501
iot 503
tham 505"
FAKE_ASUSER="|503|"
FAKE_PROBE_tham="CDM_PATH=/a/bin"
SUDO_USER=tham
PATTERNS_SRC="$CDM_ROOT/rules"
DRY_RUN=0; ASSUME_YES=0; NON_INTERACTIVE=0; PROJECTS_FLAG=0; NO_COLOR_FLAG=0
export TMPDIR SCAN_DIR CDM_PATTERNS=/nowhere CDM_REMOTE=/nowhere

# t_run — run_accounts with a fixed environment, in a subshell; prints its status.
t_run() {
    ( unset LC_ALL LC_CTYPE LC_COLLATE LC_MESSAGES LC_MONETARY LC_NUMERIC LC_TIME NO_COLOR
      export LANG=en_US.UTF-8 TERM=xterm-t
      [ -n "${T_NO_COLOR:-}" ] && export NO_COLOR=1
      run_accounts ) >/dev/null 2>&1
    echo $?
}

t_clear
assert_eq 0 "$(t_run)" "run_accounts: every account ran, status 0"
assert_eq "run.hoangnc run.iot run.tham" "$(cd "$CALLS" && ls run.* | paste -sd ' ' -)" "run_accounts: one run per account"
assert_eq "-u
tham
--
/usr/bin/env
-i
HOME=$H/tham
USER=tham
LOGNAME=tham
SHELL=/bin/zsh
PATH=/a/bin:$(t_defaults "$H/tham")
TERM=xterm-t
LANG=en_US.UTF-8
CDM_ACCOUNT=tham
CDM_ACCOUNT_POS=1/3
CDM_SUDO_BY=tham
/bin/bash
$SCAN_DIR/cdm
--patterns
$SCAN_DIR/patterns" "$(cat "$CALLS/run.tham" 2>/dev/null)" \
    "run_accounts: env -i, exactly the account's environment, the staged copy and --patterns"
assert_eq "HOME=$H/iot|CDM_ACCOUNT=iot|CDM_ACCOUNT_POS=3/3" \
    "$(grep -E '^(CDM_ACCOUNT|CDM_ACCOUNT_POS|HOME)=' "$CALLS/run.iot" | paste -sd '|' -)" "run_accounts: the third account is 3/3"
assert_fail "run_accounts: nothing like TMPDIR, SCAN_DIR or other CDM_* crosses over" \
    grep -qE '^(TMPDIR|SCAN_DIR|CDM_PATTERNS|CDM_REMOTE|SUDO_USER)=' "$CALLS/run.tham" "$CALLS/run.iot" "$CALLS/run.hoangnc"
assert_eq "503 sudo" "$(cat "$CALLS/asuser.iot" 2>/dev/null)" "run_accounts: an account with a session runs through launchctl asuser"
assert_eq "asuser.iot" "$(cd "$CALLS" && ls asuser.* | paste -sd ' ' -)" "run_accounts: ...and only that one"
assert_eq "null null null" "$(cat "$CALLS/stdin.hoangnc" "$CALLS/stdin.iot" "$CALLS/stdin.tham" 2>/dev/null | paste -sd ' ' -)" \
    "run_accounts: with no terminal, each run's stdin is /dev/null"

assert_eq "711" "$(stat -f %Lp "$SCAN_DIR")" "staged: \$SCAN_DIR is 711"
assert_eq "755" "$(stat -f %Lp "$SCAN_DIR/patterns")" "staged: the rules folder is 755"
assert_eq "644" "$(stat -f %Lp "$SCAN_DIR/cdm")" "staged: the copy is 644"
assert_ok "staged: the copy is this script" cmp -s "$CDM_BIN" "$SCAN_DIR/cdm"
t_modes=$(for f in "$SCAN_DIR/patterns"/*; do stat -f %Lp "$f"; done | sort -u | paste -sd ' ' -)
assert_eq "644" "$t_modes" "staged: every rule file is 644"
assert_ok "staged: the rules are there" test -f "$SCAN_DIR/patterns/index.json"

t_clear
DRY_RUN=1; ASSUME_YES=1; NON_INTERACTIVE=1; PROJECTS_FLAG=1; NO_COLOR_FLAG=1; T_NO_COLOR=1
t_run >/dev/null
assert_eq "NO_COLOR=1|CDM_ACCOUNT=hoangnc|CDM_ACCOUNT_POS=2/3|CDM_SUDO_BY=tham|/bin/bash|$SCAN_DIR/cdm|-n|-y|-p|--no-color|--patterns|$SCAN_DIR/patterns" \
    "$(sed -n '/^LANG=/,$p' "$CALLS/run.hoangnc" | sed 1d | paste -sd '|' -)" "run_accounts: the flags typed are passed on, in order"
DRY_RUN=0; ASSUME_YES=0; NON_INTERACTIVE=0; PROJECTS_FLAG=0; NO_COLOR_FLAG=0; T_NO_COLOR=""

t_clear
FAKE_RC_hoangnc=130
assert_eq 130 "$(t_run)" "run_accounts: an interrupted run ends root with its status"
assert_eq "run.hoangnc run.tham" "$(cd "$CALLS" && ls run.* | paste -sd ' ' -)" "run_accounts: ...and the next account never runs"

t_clear
FAKE_RC_hoangnc=1
assert_eq 0 "$(t_run)" "run_accounts: status 1 (nothing selected, a dry run) is not a stop"
assert_eq "run.hoangnc run.iot run.tham" "$(cd "$CALLS" && ls run.* | paste -sd ' ' -)" "run_accounts: ...the next account runs"
FAKE_RC_hoangnc=0

t_clear
ONLY_USERS="iot$NL"
assert_eq 0 "$(t_run)" "run_accounts --user iot"
assert_eq "run.iot" "$(cd "$CALLS" && ls run.* | paste -sd ' ' -)" "run_accounts --user: only that account"
assert_eq "CDM_ACCOUNT_POS=1/1" "$(grep '^CDM_ACCOUNT_POS=' "$CALLS/run.iot")" "run_accounts --user: counted among the chosen"
t_clear
ONLY_USERS="nobody$NL"
assert_eq 1 "$(t_run)" "run_accounts --user with an unknown name: status 1"
assert_fail "run_accounts --user with an unknown name: nothing runs" test -e "$CALLS/run.tham"
ONLY_USERS=""

# A terminal on fd 3: each run gets it as stdin. sudo runs a command whose stdin is
# not a terminal as a background job of its own pty; there the run's first stty is
# stopped and then fails with EINTR, so the mute never took and the drain before
# the menu waited for a whole line. Root runs inside a pty here, as it does from a
# terminal. see docs/DESIGN.md#sudo-accounts
t_clear
t_pty="$HOME/pty-run.sh"
cat > "$t_pty" <<'PTY'
set --
CDM_LIB=1 . "$T_CDM"
PATTERNS_SRC="$T_RULES"              # sourcing set it from CDM_PATTERNS
if [ -t 3 ]; then echo "fd3=tty"; else echo "fd3=none"; fi > "$CALLS/pty"
NON_INTERACTIVE=1                    # no prompt between accounts: nobody types here
run_accounts >/dev/null 2>&1
echo "rc=$?" >> "$CALLS/pty"
touch "$CALLS/pty.end"
PTY
( export -f dscl id launchctl sudo
  export T_CDM="$CDM_BIN" T_RULES="$PATTERNS_SRC" H CALLS FAKE_DSCL FAKE_ASUSER FAKE_PROBE_tham SUDO_USER
  # script(1) stops reading at EOF on its stdin: hold it open until the run is done.
  { i=0; while [ ! -e "$CALLS/pty.end" ] && [ "$i" -lt 600 ]; do sleep 0.05; i=$((i + 1)); done; } \
      | script -q /dev/null /bin/bash "$t_pty" >/dev/null 2>&1 )
assert_eq "fd3=tty|rc=0" "$(paste -sd '|' - < "$CALLS/pty" 2>/dev/null)" "premise: in a pty, root has a terminal on fd 3"
assert_eq "tty tty tty" "$(cat "$CALLS/stdin.hoangnc" "$CALLS/stdin.iot" "$CALLS/stdin.tham" 2>/dev/null | paste -sd ' ' -)" \
    "run_accounts: with a terminal, each run gets it as stdin"

t_clear
FAKE_DSCL="root 0"
assert_eq 1 "$(t_run)" "run_accounts: no account at all is an error"
unset CDM_PATTERNS CDM_REMOTE

# ---- the bootstrap: root reading the script from stdin -----------------------------
#
# The block is cut out of cdm between its markers and only its root test replaced,
# so this runs the real code as the normal user. Each run leaves a folder in
# /private/tmp, removed below.

t_block=$(awk '/^# Root with no file to run from/ { on = 1 } on { print } on && /^fi$/ { exit }' "$CDM_BIN")
t_block=${t_block/'[ "${EUID:-}" = 0 ]'/true}
case "$t_block" in "# Root with no file"*'/bin/bash "$_cdm_d/cdm" "$@" < /dev/null'*fi) r=ok ;; *) r="$t_block" ;; esac
assert_eq ok "$r" "bootstrap: the block is found between its markers"
# The rest prints where it ran from, its arguments, then the copy itself: the copy's
# folder is gone by the time the bootstrap returns, so it is read from the inside.
t_harness="#!/bin/bash
set -u
$t_block
printf '%s|' RAN \"\${BASH_SOURCE[0]}\" \"\$@\"; echo; cat \"\${BASH_SOURCE[0]}\"
"
t_before=$(ls -d /private/tmp/cdm.?????? 2>/dev/null)
t_new_dirs() {
    local d
    for d in /private/tmp/cdm.??????; do
        [ -d "$d" ] && [ -O "$d" ] || continue
        case "$NL$t_before$NL" in *"$NL$d$NL"*) continue ;; esac
        printf '%s\n' "$d"
    done
}
t_check_ran() { # <output> <desc>
    case "${1%%$NL*}" in "RAN|/private/tmp/cdm."??????"/cdm|a|b c|") r=ok ;; *) r="[$1]" ;; esac
    assert_eq ok "$r" "$2"
}

t_out=$(printf '%s' "$t_harness" | /bin/bash -s -- a 'b c' 2>&1)
t_check_ran "$t_out" "bootstrap: piped, the rest ran from a copy in /private/tmp, arguments intact"
assert_eq "#!/bin/bash
set -u
printf '%s|' RAN \"\${BASH_SOURCE[0]}\" \"\$@\"; echo; cat \"\${BASH_SOURCE[0]}\"" \
    "${t_out#*$NL}" "bootstrap: piped, the copy is the rest of the script"
assert_eq "" "$(t_new_dirs)" "bootstrap: piped, the copy's folder is gone once the run ends"
for d in $(t_new_dirs); do rm -rf "$d"; done

t_out=$(/bin/bash -c "$t_harness" bash a 'b c' 2>&1)
t_check_ran "$t_out" "bootstrap: bash -c, the script ran from a copy in /private/tmp, arguments intact"
assert_eq "" "$(t_new_dirs)" "bootstrap: bash -c, the copy's folder is gone once the run ends"
for d in $(t_new_dirs); do rm -rf "$d"; done

# An early exit in the copy (--help, a bad option) comes before its own cleanup trap:
# the bootstrap still removes the folder, and passes the status on.
t_early="#!/bin/bash
set -u
$t_block
exit 3
"
printf '%s' "$t_early" | /bin/bash -s 2>/dev/null; t_rc=$?
assert_eq 3 "$t_rc" "bootstrap: the copy's exit status is root's"
assert_eq "" "$(t_new_dirs)" "bootstrap: an early exit in the copy leaves no folder behind"
for d in $(t_new_dirs); do rm -rf "$d"; done

# ---- --user without sudo ----------------------------------------------------------

t_out=$(/bin/bash "$CDM_BIN" --user nosuchuser -h 2>&1); t_rc=$?
assert_eq 1 "$t_rc" "--user someone else without sudo: exit 1"
assert_ok "...saying it needs sudo, with the command" grep -q "^  curl .* | sudo bash -s -- --user nosuchuser$" <<EOF
$t_out
EOF
assert_ok "--user yourself without sudo is accepted" /bin/bash "$CDM_BIN" --user "$(command id -un)" -h

# ---- each account's run: the menu title and the log receipt -----------------------

t_frame() {
    TERM_ROWS="$1"; TERM_COLS="$2"; SIZE_STALE=0
    render_menu | sed "s/$(printf '\033')\[[0-9;?]*[A-Za-z]//g"
}
t_widest() {
    local l w=0
    while IFS= read -r l; do dwidth "$l"; [ "$_DW" -gt "$w" ] && w=$_DW; done <<EOF
$(t_frame "$1" "$2")
EOF
    echo "$w"
}
CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=(); CAT_PATHS=()
CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=(); CAT_PROCS=(); N=0
add_category "x" "row" "desc" rm 0 "/nowhere"; CAT_KB[0]=1000
CURSOR=0; SCROLL=0; DRY_RUN=0; RESTART_NOTE=""
DISK_TOTAL_KB=239362496; DISK_USED_KB=238916852; DISK_FREE_KB=445644

unset CDM_ACCOUNT CDM_ACCOUNT_POS
t_plain=$(t_frame 24 100 | sed -n 1p)
dwidth "$t_plain"; t_plain_w=$_DW
CDM_ACCOUNT=tham CDM_ACCOUNT_POS=3/5
assert_eq "🧹 CleanDevMac — tham · 3/5" "$(t_frame 24 100 | sed -n 1p)" "the title names the account and its place"
assert_ok "no frame line is wider than the terminal" test "$(t_widest 24 60)" -le 60
CDM_ACCOUNT=averyveryverylongaccountname
t_title=$(t_frame 24 100 | sed -n 1p)
dwidth "$t_title"
assert_ok "a long account name: the title is no wider than before ($_DW <= $t_plain_w)" test "$_DW" -le "$t_plain_w"
assert_eq "🧹 CleanDevMac — averyveryv… · 3/5" "$t_title" "a long account name is clipped, its place kept"
unset CDM_ACCOUNT CDM_ACCOUNT_POS

CACHE="$HOME/Library/Caches/Faux"; mkdir -p "$CACHE"; : > "$CACHE/blob"
CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=(); CAT_PATHS=()
CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=(); CAT_PROCS=(); N=0
add_category "x" "Faux cache" "d" rm 1 "$CACHE"; CAT_KB[0]=4; CAT_SEL[0]=1
NON_INTERACTIVE=1; DRY_RUN=0
CDM_SUDO_BY=hoangnc
run_cleanup >/dev/null 2>&1
assert_eq "Run with sudo by hoangnc" "$(sed -n '/^CleanDevMac run: /{n;p;}' "$LOG_FILE" | tail -n 1)" \
    "the log receipt says who ran sudo, right under the date"
assert_fail "...and the clean ran" test -e "$CACHE"
unset CDM_SUDO_BY
mkdir -p "$CACHE"; : > "$CACHE/blob"
run_cleanup >/dev/null 2>&1
assert_eq 1 "$(grep -c '^Run with sudo by' "$LOG_FILE")" "a run without sudo says nothing of it"
NON_INTERACTIVE=0

test_summary
