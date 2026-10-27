#!/bin/bash
# The "rust-docs" rule kind (register_rust_docs, run_rustup_docs_remove) — one row
# for the rust-docs component of every toolchain that has it, sized from its html
# folder and removed with `rustup component remove rust-docs`, never rm.
# See docs/DESIGN.md#rust-docs.
#
# What the assertions below are shaped around:
#
#   * offered only where rustup's own components file lists rust-docs: a folder
#     by that name is not the component, and rm'ing it behind rustup's back
#     leaves a manifest pointing at files that are gone.
#   * kept out: a linked toolchain (someone's own build) and any name rustup
#     would not have written.
#   * the clean runs rustup, pointed at the rustup home the docs were found in.
#     rustup is a shell function here that logs what it was asked.

. "$(dirname "$0")/lib.sh"

reset_cats() { CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=(); CAT_DEFAULT=()
               CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); CAT_PMETHOD=(); CAT_SUMMARY=()
               CAT_PROCS=(); N=0; PARSED_OK=0; }

T_LOG="$HOME/rustup-calls.log"; : > "$T_LOG"
rustup() { printf '%s|%s\n' "${RUSTUP_HOME:-}" "$*" >> "$T_LOG"; echo "info: removing component"; }

RH="$HOME/.rustup"
# mktc <dir> <component...> — a toolchain with docs whose components file lists those.
mktc() {
    local t="$1"; shift
    mkdir -p "$t/lib/rustlib" "$t/share/doc/rust/html/std"
    echo x > "$t/share/doc/rust/html/std/index.html"
    printf '%s\n' "$@" > "$t/lib/rustlib/components"
}
mktc "$RH/toolchains/stable-aarch64-apple-darwin" rustc-aarch64-apple-darwin rust-docs-aarch64-apple-darwin
mktc "$RH/toolchains/1.98-aarch64-apple-darwin" rust-docs-aarch64-apple-darwin
mktc "$RH/toolchains/nightly-aarch64-apple-darwin" rustc-aarch64-apple-darwin cargo-aarch64-apple-darwin
mktc "$RH/toolchains/-evil" rust-docs-aarch64-apple-darwin
mktc "$HOME/my-rust" rust-docs-aarch64-apple-darwin
ln -s "$HOME/my-rust" "$RH/toolchains/mine"
mkdir -p "$RH/toolchains/1.80-aarch64-apple-darwin/lib/rustlib"
echo rust-docs-aarch64-apple-darwin > "$RH/toolchains/1.80-aarch64-apple-darwin/lib/rustlib/components"

# ---- register_rust_docs ----------------------------------------------------------

reset_cats
register_rust_docs "📖" "Rust offline docs" 0 "D." "~/.rustup/toolchains/*"
assert_eq "1" "$N" "one row"
assert_eq "$RH/toolchains/1.98-aarch64-apple-darwin/share/doc/rust/html
$RH/toolchains/stable-aarch64-apple-darwin/share/doc/rust/html" "${CAT_PATHS[0]:-}" \
    "offered: the docs of each toolchain whose components list rust-docs"
assert_eq "rustdocs|0|1.98-aarch64-apple-darwin, stable-aarch64-apple-darwin" \
    "${CAT_METHOD[0]:-}|${CAT_DEFAULT[0]:-}|${CAT_SUMMARY[0]:-}" "removed by rustup, unchecked, naming the toolchains"
assert_eq "rustup" "$RUSTUP_BIN" "the rustup found on PATH is the one the clean will run"

# ---- the clean -------------------------------------------------------------------------

: > "$T_LOG"
CAT_SEL[0]=1; CAT_KB[0]=1024; NON_INTERACTIVE=1; DRY_RUN=0
t_out=$(run_cleanup 2>&1)
assert_ok "the plan marks the row UNINSTALL" grep -q 'UNINSTALL.*Rust offline docs' <<EOF
$t_out
EOF
assert_eq "$RH|component remove rust-docs --toolchain 1.98-aarch64-apple-darwin
$RH|component remove rust-docs --toolchain stable-aarch64-apple-darwin" "$(cat "$T_LOG")" \
    "the clean runs rustup for each toolchain, with RUSTUP_HOME set"
assert_ok "...and deletes nothing itself" test -d "$RH/toolchains/stable-aarch64-apple-darwin/share/doc/rust/html"
CAT_SEL[0]=0; NON_INTERACTIVE=0
CURSOR=0
assert_ok "details name rustup as the action" grep -q "remove with 'rustup component remove rust-docs'" <<EOF
$(show_details 2>&1)
EOF

# ---- run_rustup_docs_remove ----------------------------------------------------------

: > "$T_LOG"
run_rustup_docs_remove "$RH/toolchains/1.98-aarch64-apple-darwin/share/doc/rust/html
$RH/toolchains/-evil/share/doc/rust/html
$RH/toolchains/stable-aarch64-apple-darwin/share/doc
/etc/toolchains/1.98-aarch64-apple-darwin/share/doc/rust/html" >/dev/null 2>&1
assert_eq "$RH|component remove rust-docs --toolchain 1.98-aarch64-apple-darwin" "$(cat "$T_LOG")" \
    "only a toolchain's own docs folder is removed; an odd name, another folder and a path off \$HOME are skipped"
: > "$T_LOG"
t_out=$( RUSTUP_BIN=""; run_rustup_docs_remove "$RH/toolchains/1.98-aarch64-apple-darwin/share/doc/rust/html" 2>&1 )
assert_eq "" "$(cat "$T_LOG")" "no rustup known: nothing is run"
assert_ok "...and the receipt says why" grep -q 'skip (no rustup): 1.98-aarch64-apple-darwin' <<EOF
$t_out
EOF

# No rustup anywhere: nothing can be removed properly, so nothing is offered.
reset_cats
( unset -f rustup; PATH=/usr/bin:/bin; CARGO_HOME="$HOME/no-cargo"
  register_rust_docs "📖" "Rust offline docs" 0 "D." "~/.rustup/toolchains/*"; echo "$N" ) > "$HOME/n" 2>/dev/null
assert_eq "0" "$(cat "$HOME/n")" "no rustup: no row"

# ---- the shipped rule -------------------------------------------------------------------

reset_cats
parse_pattern_stream "$CDM_ROOT/rules/dev-caches.json"
t_row=""
for i in $(cat_indices); do
    [ "${CAT_METHOD[$i]}" = "rustdocs" ] && t_row="${CAT_NAME[$i]}|${CAT_DEFAULT[$i]}"
done
assert_eq "Rust offline docs|0" "$t_row" "shipped dev-caches.json: the rust-docs row, unchecked"

test_summary
