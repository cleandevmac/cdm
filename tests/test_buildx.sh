#!/bin/bash
# The buildx half of the container category (docs/DESIGN.md#buildx-builders):
# buildx_name_ok (what may reach a command), buildx_cache_rows (what is
# measured), scan_containers (where it lands) and prune_buildx_caches as
# run_container_prune calls it (what runs, in which order).
#
# What the assertions below are shaped around:
#
#   * a docker-container builder keeps its BuildKit cache in the named volume
#     buildx_buildkit_<node>_state, which `system df` counts as an in-use
#     volume — so the Build Cache line never shows it and `system prune -af`
#     never frees it. A real 10.58 GB builder read as 1.9 MB of build cache.
#     The fixtures are that machine's output (docker 29.8.2, buildx 0.37.2).
#   * docker is a shell function here, and it answers ONLY the exact --format
#     strings cdm must send. Both were found the hard way: .Driver is not a
#     field of buildx ls's template, and {{"\n"}} breaks docker's (it turns \n
#     into a newline before Go parses the template). A fake that answered any
#     `buildx ls` would let either regression pass.
#   * a node with no container (inactive) is left out however large its volume:
#     starting it again can need its image pulled, and cdm makes no network
#     calls.
#   * order is the clean's whole correctness: a stopped builder is started,
#     pruned and stopped again, and all of it BEFORE `system prune -af`, which
#     would remove the stopped container and then its image. A call log pins it.

. "$(dirname "$0")/lib.sh"

# ---- fake docker ------------------------------------------------------------

T_LS_FMT='{{.Name}}|{{.DriverEndpoint}}|{{.Status}}'
T_VOL_FMT='{{range .Volumes}}{{.Name}}|{{.Size}}{{println}}{{end}}'
T_LOG="$HOME/docker-calls.log"
: > "$T_LOG"
t_ls=""; t_vols=""; t_ls_rc=0; t_boot_rc=0; t_bc="1.919MB"

docker() {
    printf '%s\n' "$*" >> "$T_LOG"
    if [ "$1 $2 $3" = "buildx ls --format" ]; then
        [ "$4" = "$T_LS_FMT" ] || return 1
        [ -n "$t_ls" ] && printf '%s\n' "$t_ls"
        return "$t_ls_rc"
    fi
    if [ "$1 $2 $3 $4" = "system df -v --format" ]; then
        [ "$5" = "$T_VOL_FMT" ] || return 1
        [ -n "$t_vols" ] && printf '%s\n' "$t_vols"
        return 0
    fi
    if [ "$1 $2 $3" = "system df --format" ]; then
        printf '%s\n' 'Images|0B (0%)' 'Containers|0B (0%)' \
            'Local Volumes|10.58GB (0%)' "Build Cache|$t_bc"
        return 0
    fi
    [ "$1 $2" = "buildx inspect" ] && return "$t_boot_rc"
    return 0
}
podman() { printf 'podman %s\n' "$*" >> "$T_LOG"; }

# t_calls — the mutating calls the clean made, in order, "|"-joined.
t_calls() {
    grep -E '^(buildx (inspect|prune|stop)|system prune|podman system prune)' "$T_LOG" | tr '\n' '|' | sed 's/|$//'
}

# The real machine: pihome running with 10.58 GB of cache, iotcore with no
# container (and, here, a leftover volume), and the two docker-driver builders
# every install has.
REAL_LS='pihome|docker-container|
pihome0|orbstack|running
iotcore|docker-container|
iotcore0|orbstack|inactive
default|docker|
default|default|running
orbstack|docker|
orbstack|orbstack|running'
REAL_VOLS='b5865b344762b0b04981e802e5e011db2a14f0b1ef0595ab76fb2d42b56820ba|1.94MB
buildx_buildkit_pihome0_state|10.58GB
buildx_buildkit_iotcore0_state|2.5GB'
# A stopped builder — the throwaway one these facts were checked with.
STOPPED_LS='cdmtest|docker-container|
cdmtest0|orbstack|stopped'
STOPPED_VOLS='buildx_buildkit_cdmtest0_state|63.41MB'

# ---- buildx_name_ok ---------------------------------------------------------

for n in pihome my.builder_1-x 0builder A; do
    assert_ok "builder name '$n' is accepted" buildx_name_ok "$n"
done
for n in "" -x .x _x "a b" "a;b" a/b "a|b" 'b$(x)' 名前; do
    assert_fail "builder name '$n' is refused" buildx_name_ok "$n"
done

# ---- buildx_cache_rows ------------------------------------------------------

t_ls="$REAL_LS"; t_vols="$REAL_VOLS"
assert_eq "pihome|running|10332031" "$(buildx_cache_rows)" \
    "the real machine: only the running docker-container builder, at its volume's size"

t_ls="$REAL_LS
$STOPPED_LS"; t_vols="$REAL_VOLS
$STOPPED_VOLS"
assert_eq "pihome|running|10332031
cdmtest|stopped|61923" "$(buildx_cache_rows)" "a stopped builder is a row too, marked stopped"

# A docker-driver builder whose node name matches a leftover state volume (a
# docker-container builder of the same name, since recreated): pruning it would
# clear the daemon's own cache, never that volume.
t_ls='legacy|docker|
legacy0|default|running'; t_vols='buildx_buildkit_legacy0_state|5GB'
assert_eq "" "$(buildx_cache_rows)" "a docker-driver builder is never a row"

t_ls='empty|docker-container|
empty0|orbstack|running'; t_vols='buildx_buildkit_empty0_state|0B'
assert_eq "" "$(buildx_cache_rows)" "an empty cache is not a row"

# What a prune leaves behind — measured at 487 KiB of BuildKit bookkeeping on the
# real engine — is not a cache: offered, every clean would leave a row behind.
t_ls='after|docker-container|
after0|orbstack|running'; t_vols='buildx_buildkit_after0_state|498.7kB'
assert_eq "" "$(buildx_cache_rows)" "a pruned builder's bookkeeping is not offered"

t_ls='nodey|docker-container|
-x0|orbstack|running'; t_vols='buildx_buildkit_-x0_state|1GB'
assert_eq "" "$(buildx_cache_rows)" "a node name buildx would refuse is skipped"

t_ls='ev il|docker-container|
evil0|orbstack|running'; t_vols='buildx_buildkit_evil0_state|1GB'
assert_eq "" "$(buildx_cache_rows)" "a builder name buildx would refuse is skipped"

# Nodes add up, and one stopped node makes the builder stopped — but a node
# with no cache of its own says nothing about the builder's state.
t_ls='multi|docker-container|
multi0|orbstack|running
multi1|orbstack|stopped'; t_vols='buildx_buildkit_multi0_state|1GB
buildx_buildkit_multi1_state|2GB'
assert_eq "multi|stopped|2929687" "$(buildx_cache_rows)" "a builder's nodes are summed; any stopped node stops it"
t_ls='mixed|docker-container|
mixed0|orbstack|running
mixed1|orbstack|stopped'; t_vols='buildx_buildkit_mixed0_state|1GB'
assert_eq "mixed|running|976562" "$(buildx_cache_rows)" "a node with no cache does not decide the state"

# No buildx (or one older than --format): nothing, and no error.
t_ls="docker: 'buildx' is not a docker command."; t_ls_rc=1; t_vols="$REAL_VOLS"
assert_eq "" "$(buildx_cache_rows)" "a docker without buildx yields no rows"
t_ls_rc=0

# ---- scan_containers --------------------------------------------------------

reset_containers() {
    CAT_ICON=(); CAT_NAME=(); CAT_DESC=(); CAT_METHOD=()
    CAT_DEFAULT=(); CAT_PATHS=(); CAT_KB=(); CAT_SEL=(); N=0
    CAT_PMETHOD=(); CAT_SUMMARY=(); CAT_PROCS=()
    CONT_ICON=("🐳"); CONT_NAME=("Docker"); CONT_METHOD=("prune"); CONT_DEFAULT=("false")
    CONT_DESC=("desc"); CONT_ENGINES=("docker"); CONT_N=1
}

t_ls="$REAL_LS
$STOPPED_LS"; t_vols="$REAL_VOLS
$STOPPED_VOLS"
reset_containers; scan_containers
assert_eq "1|10395828" "$N|${CAT_KB[0]:-}" \
    "the docker row adds every builder cache to system df's 1.9 MB of build cache"

# Builder caches alone are enough to offer the row.
t_bc="0B"
reset_containers; scan_containers
assert_eq "1|10393954" "$N|${CAT_KB[0]:-}" "builder caches alone register the docker row"
t_ls=""
reset_containers; scan_containers
assert_eq "0" "$N" "nothing reclaimable registers nothing"
t_bc="1.919MB"

# ---- the clean: what runs, in which order -----------------------------------

t_ls="$REAL_LS
$STOPPED_LS"; t_vols="$REAL_VOLS
$STOPPED_VOLS"
: > "$T_LOG"
run_container_prune "docker" >/dev/null 2>&1
assert_eq "buildx prune --builder pihome -af|buildx inspect --bootstrap cdmtest|buildx prune --builder cdmtest -af|buildx stop cdmtest|system prune -af" \
    "$(t_calls)" "running: prune; stopped: start, prune, stop; then system prune — in that order"

# A builder that will not start keeps its cache, and the clean goes on.
t_boot_rc=1
: > "$T_LOG"
run_container_prune "docker" >/dev/null 2>&1
assert_eq "buildx prune --builder pihome -af|buildx inspect --bootstrap cdmtest|system prune -af" \
    "$(t_calls)" "a builder that fails to start is neither pruned nor stopped"
t_boot_rc=0

# buildx is docker's: another engine gets its own prune and nothing else.
: > "$T_LOG"
run_container_prune "podman" >/dev/null 2>&1
assert_eq "podman system prune -af" "$(t_calls)" "podman runs no buildx"

test_summary
