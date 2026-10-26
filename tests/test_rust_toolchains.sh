#!/bin/bash
# The "rust-toolchains" rule kind (cdm's scan_toolchains and its helpers) — one
# row per installed Rust toolchain that is neither the default nor stable, sized
# from its folder and removed with `rustup toolchain uninstall`, never rm. Each
# row names the repos that pin it. See docs/DESIGN.md#rust-toolchains.
#
# What the assertions below are shaped around:
#
#   * what is KEPT: the default toolchain, every stable-*, a linked toolchain
#     (rustup toolchain link — someone's own build, nothing to download), and
#     any name rustup would not have written. Most assertions are about those.
#   * a pin is matched to a toolchain the way rustup resolves it: channel "1.98"
#     installs 1.98-<host>, but channel "nightly" is not nightly-2026-01-01-<host>.
#   * pins are found the way the project scan finds repos — its roots, depth and
#     prune list, and its junk dir names, so a crate vendored under node_modules
#     never reads as one of your repos pinning something.
#   * the clean runs rustup, pointed at the rustup home the toolchain was found
#     in. rustup is a shell function here that logs what it was asked.

. "$(dirname "$0")/lib.sh"

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0; }

T_LOG="$HOME/rustup-calls.log"; : > "$T_LOG"
rustup() { printf '%s|%s\n' "${RUSTUP_HOME:-}" "$*" >> "$T_LOG"; echo "info: uninstalled"; }

RH="$HOME/.rustup"
mktc() { mkdir -p "$RH/toolchains/$1/bin"; echo x > "$RH/toolchains/$1/bin/rustc"; }
mktc stable-aarch64-apple-darwin
mktc stable-x86_64-apple-darwin
mktc 1.98-aarch64-apple-darwin
mktc nightly-2026-01-01-aarch64-apple-darwin
mktc 1.80-aarch64-apple-darwin
mkdir -p "$HOME/my-rust-build/bin"; echo x > "$HOME/my-rust-build/bin/rustc"
ln -s "$HOME/my-rust-build" "$RH/toolchains/mine"
mkdir -p "$RH/toolchains/-evil"; echo x > "$RH/toolchains/-evil/f"
printf 'version = "12"\ndefault_toolchain = "1.80-aarch64-apple-darwin"\nprofile = "default"\n\n[overrides]\n"%s/work/legacy" = "nightly-2026-01-01-aarch64-apple-darwin"\n' "$HOME" > "$RH/settings.toml"

# Repos that pin, the way the scan finds them.
mkdir -p "$HOME/code/app" "$HOME/code/old" "$HOME/code/web/node_modules/napi-crate" "$HOME/code/nightly"
printf '# pinned on purpose\n[toolchain]\nchannel = "1.98"   # edition 2024\ncomponents = ["clippy"]\n' > "$HOME/code/app/rust-toolchain.toml"
printf '1.98\n' > "$HOME/code/old/rust-toolchain"
printf '[toolchain]\nchannel = "1.98"\n' > "$HOME/code/web/node_modules/napi-crate/rust-toolchain.toml"
printf "[toolchain]\nchannel = 'nightly'\n" > "$HOME/code/nightly/rust-toolchain.toml"
mkdir -p "$HOME/code/app/vendor/some-crate"
printf '[toolchain]\nchannel = "1.98"\n' > "$HOME/code/app/vendor/some-crate/rust-toolchain.toml"
SCAN_ROOTS=("~/code"); SCAN_PRUNE=(".git" "vendor"); SCAN_DEPTH=6
PROJ_N=1; PROJ_DIRS=("node_modules
target")

# ---- toolchain_name_ok ----------------------------------------------------------

for n in 1.98-aarch64-apple-darwin nightly-2026-01-01-x86_64-apple-darwin stable-aarch64-apple-darwin; do
    assert_ok "toolchain name '$n' is accepted" toolchain_name_ok "$n"
done
for n in "" -evil .hidden "a b" "a;b" 'x$(id)' ナイトリー; do
    assert_fail "toolchain name '$n' is refused" toolchain_name_ok "$n"
done

# ---- toolchain_is ----------------------------------------------------------------

assert_ok   "1.98 installs 1.98-aarch64-apple-darwin"   toolchain_is 1.98-aarch64-apple-darwin 1.98
assert_ok   "a full name matches itself"                 toolchain_is 1.98-aarch64-apple-darwin 1.98-aarch64-apple-darwin
assert_ok   "nightly installs nightly-x86_64-apple-darwin" toolchain_is nightly-x86_64-apple-darwin nightly
assert_fail "nightly is not a dated nightly"             toolchain_is nightly-2026-01-01-aarch64-apple-darwin nightly
assert_fail "1.9 is not 1.98"                            toolchain_is 1.98-aarch64-apple-darwin 1.9
assert_fail "1.98 is not 1.98.1"                         toolchain_is 1.98.1-aarch64-apple-darwin 1.98

# ---- toolchain_file_channel ----------------------------------------------------------

assert_eq "1.98"    "$(toolchain_file_channel "$HOME/code/app/rust-toolchain.toml")" "TOML: the quoted channel, comment and all"
assert_eq "1.98"    "$(toolchain_file_channel "$HOME/code/old/rust-toolchain")" "legacy file: its bare first line"
assert_eq "nightly" "$(toolchain_file_channel "$HOME/code/nightly/rust-toolchain.toml")" "TOML: a single-quoted channel"
printf '[toolchain]\npath = "/opt/my-rust"\n' > "$HOME/pathpin.toml"
assert_eq "" "$(toolchain_file_channel "$HOME/pathpin.toml")" "a path toolchain pins no channel"
printf 'stable\n' > "$HOME/rust-toolchain.toml"
assert_eq "" "$(toolchain_file_channel "$HOME/rust-toolchain.toml")" "a bare line only counts in a legacy rust-toolchain"

# ---- rustup_default --------------------------------------------------------------------

assert_eq "1.80-aarch64-apple-darwin" "$(rustup_default "$RH")" "the default from settings.toml"
assert_eq "" "$(rustup_default "$HOME/none")" "no settings.toml: no default"

# ---- toolchain_pins ----------------------------------------------------------------------

t_pins=$(toolchain_pins "$RH" | tr '\037' '|' | LC_ALL=C sort)
assert_eq "$HOME/code/app|1.98
$HOME/code/nightly|nightly
$HOME/code/old|1.98
$HOME/work/legacy|nightly-2026-01-01-aarch64-apple-darwin" "$t_pins" \
    "pins from both file kinds and rustup's overrides; nothing under a pruned or junk dir"

# ---- scan_toolchains ------------------------------------------------------------------------

reset_cats
TC_ON=1; TC_ICON="🦀"; TC_NAME="Rust toolchain"; TC_DEFAULT=0; TC_DESC="D."; TC_GLOBS="~/.rustup/toolchains/*"
scan_toolchains
t_rows=""
for i in $(cat_indices); do t_rows="${t_rows}${CAT_NAME[$i]}|${CAT_METHOD[$i]}|${CAT_SUMMARY[$i]};"; done
assert_eq "Rust toolchain: 1.98-aarch64-apple-darwin|rustup|pinned by ~/code/app, ~/code/old;Rust toolchain: nightly-2026-01-01-aarch64-apple-darwin|rustup|pinned by ~/work/legacy;" \
    "$t_rows" "offered: 1.98 and the dated nightly, with their pins; kept: stable, the default, linked, odd names"
assert_eq "$RH/toolchains/1.98-aarch64-apple-darwin" "${CAT_PATHS[0]:-}" "the row's path is the toolchain's folder"
assert_eq "D. Pinned by ~/code/app, ~/code/old, whose next build downloads it again." "${CAT_DESC[0]:-}" \
    "the description says which repos would download it again"
assert_eq "0" "${CAT_DEFAULT[0]:-}" "the rule's default is kept"
assert_eq "rustup" "$RUSTUP_BIN" "the rustup found on PATH is the one the clean will run"

# The clean: the plan says UNINSTALL, rustup is what runs, and cdm itself removes
# nothing — the fake rustup deletes nothing, so the folder must still be there.
: > "$T_LOG"
CAT_SEL[0]=1; CAT_KB[0]=1024; NON_INTERACTIVE=1; DRY_RUN=0
t_out=$(run_cleanup 2>&1)
assert_ok "the plan marks the row UNINSTALL" grep -q 'UNINSTALL.*Rust toolchain: 1.98-aarch64-apple-darwin' <<EOF
$t_out
EOF
assert_eq "$RH|toolchain uninstall 1.98-aarch64-apple-darwin" "$(cat "$T_LOG")" "the clean runs rustup for the row"
assert_ok "...and deletes nothing itself" test -d "$RH/toolchains/1.98-aarch64-apple-darwin"
CAT_SEL[0]=0; NON_INTERACTIVE=0
CURSOR=0
assert_ok "details name rustup as the action" grep -q "uninstall with 'rustup toolchain uninstall'" <<EOF
$(show_details 2>&1)
EOF

# A bare channel as the default keeps the toolchain it installs.
sed -i '' 's/^default_toolchain = .*/default_toolchain = "nightly-2026-01-01"/' "$RH/settings.toml"
reset_cats; scan_toolchains
t_rows=""; for i in $(cat_indices); do t_rows="${t_rows}${CAT_NAME[$i]};"; done
assert_eq "Rust toolchain: 1.80-aarch64-apple-darwin;Rust toolchain: 1.98-aarch64-apple-darwin;" "$t_rows" \
    "a default given as a channel keeps the toolchain it names"

# No rustup anywhere: nothing can be uninstalled properly, so nothing is offered.
reset_cats
( unset -f rustup; PATH=/usr/bin:/bin; CARGO_HOME="$HOME/no-cargo"; scan_toolchains; echo "$N" ) > "$HOME/n" 2>/dev/null
assert_eq "0" "$(cat "$HOME/n")" "no rustup: no rows"

# Only the default and stable installed: nothing to offer.
rm -rf "$RH/toolchains/1.98-aarch64-apple-darwin" "$RH/toolchains/1.80-aarch64-apple-darwin"
reset_cats; scan_toolchains
assert_eq "0" "$N" "nothing but the default and stable: no rows"

# ---- run_rustup_uninstall --------------------------------------------------------------------

: > "$T_LOG"
run_rustup_uninstall "$RH/toolchains/nightly-2026-01-01-aarch64-apple-darwin
$RH/toolchains/-evil
/etc/toolchains/1.98-aarch64-apple-darwin" >/dev/null 2>&1
assert_eq "$RH|toolchain uninstall nightly-2026-01-01-aarch64-apple-darwin" "$(cat "$T_LOG")" \
    "uninstalled by name through rustup, with RUSTUP_HOME set; an odd name and a path off \$HOME are skipped"
: > "$T_LOG"
t_out=$( RUSTUP_BIN=""; run_rustup_uninstall "$RH/toolchains/nightly-2026-01-01-aarch64-apple-darwin" 2>&1 )
assert_eq "" "$(cat "$T_LOG")" "no rustup known: nothing is run"
assert_ok "...and the receipt says why" grep -q 'skip (no rustup): nightly-2026-01-01-aarch64-apple-darwin' <<EOF
$t_out
EOF

# ---- the rule round-trip ------------------------------------------------------------------------

# The kind waits for scan_toolchains: parsing only queues it.
RULES=$(mktemp -d "$HOME/rules.XXXXXX")
cat > "$RULES/rust.json" <<'JSON'
{ "categories": [ {
    "kind": "rust-toolchains", "icon": "x", "name": "Rust toolchain",
    "method": "rm", "default": false, "desc": "d",
    "candidates": [ "~/.rustup/toolchains/*" ]
} ] }
JSON
reset_cats; TC_ON=0; TC_GLOBS=""; PARSED_OK=0
parse_pattern_stream "$RULES/rust.json"
assert_eq "0|1|~/.rustup/toolchains/*" "$N|$TC_ON|$TC_GLOBS" "a rust-toolchains rule is queued, not registered, with its globs"
mktc 1.98-aarch64-apple-darwin
scan_toolchains
assert_eq "rustup" "${CAT_METHOD[0]:-}" "a rule asking for rm still gets rustup"
reset_cats; TC_ON=0; TC_GLOBS=""; PARSED_OK=0
parse_pattern_stream "$CDM_ROOT/rules/dev-caches.json"
assert_eq "1|~/.rustup/toolchains/*|0" "$TC_ON|$TC_GLOBS|$TC_DEFAULT" "shipped dev-caches.json: the rustup toolchains, unchecked"
sed 's/"kind": "rust-toolchains"/"kind": "some-future-kind"/' "$RULES/rust.json" > "$RULES/old.json"
reset_cats; TC_ON=0; PARSED_OK=0
parse_pattern_stream "$RULES/old.json"
assert_eq "0|0" "$N|$TC_ON" "unknown kind with only 'candidates' registers nothing"

test_summary
