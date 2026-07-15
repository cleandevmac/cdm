# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

CleanDevMac (`cdm`) is a single ~1500-line bash script that reclaims disk space on macOS from
developer caches, build artifacts, per-repo project junk, Docker/Podman, and orphaned app data.
`cdm` is the whole program — `rules/*.json` is its data. There is no build step, no dependency
manifest, and no test framework.

Users run it by piping a GitHub release asset straight into bash:

```bash
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm | bash
```

That distribution model drives most of the non-obvious decisions below.

## Commands

There is nothing to build or install. Verification is by running the thing.

```bash
bash -n cdm                  # syntax check — the same guard CI runs before releasing
./cdm --help                 # renders usage; also proves top-level vars resolve
./cdm --dry-run              # full scan, deletes nothing. The main manual test.
./cdm --dry-run --no-color   # readable when piping output somewhere
./cdm --patterns ./rules     # force a specific rule source
```

Exercising a single unit: source the script without running it. The test hook at the bottom of
`cdm` returns early when `CDM_LIB=1`, so functions load into your shell with no scan and no TUI.

```bash
CDM_LIB=1 . ./cdm
SCAN_DIR=$(mktemp -d)        # most functions need this set
resolve_patterns && ls "$PATTERNS_DIR"
is_safe_target "$HOME/Documents" && echo REACHABLE || echo "correctly refused"
```

`shellcheck` is not installed and is not a dependency — don't add it to a workflow without asking.

### Verifying the piped path

A change can pass `./cdm --dry-run` and still break the way ~everyone runs it. Test the pipe:

```bash
cat cdm | bash -s -- --help
cat cdm | bash -s -- -n
```

`curl: (56) Failure writing output to destination` on a short-circuiting flag like `--help` is
expected, not a bug: bash exits without draining the pipe and curl takes SIGPIPE.

## Architecture

### Rules are data; the script is an interpreter

`rules/index.json` is the manifest — it lists which files load and in what order. Each pattern file
contributes categories. Adding or removing cleanup targets should be a JSON edit, **not** a code
change; the README and landing page both promise this, so preserve it.

A category object is `icon`, `name`, `desc`, `method`, `default`, `paths`:

- `method` — `rm` (permanent; the target regenerates) or `trash` (recoverable). Also `project`
  and `container`, which the script synthesizes rather than reading verbatim.
- `default` — whether it arrives pre-selected. `s` in the TUI resets to these.
- `desc` — the *why*, shown next to the row.

Note the on-disk names are `name`/`method`/`default`, not `label`/`disposition`/`safe`. If you are
writing docs, read a rule file first — this has been documented wrong before.

### Rule resolution order (`resolve_patterns`)

`--patterns` → `<script-dir>/rules` → `<script-dir>/../rules` → `~/.cleandevmac/rules` →
`$REMOTE_BASE` (raw main on GitHub).

When piped from curl, **`BASH_SOURCE` is unset** (`$0` is `bash`), so the `*/*` case never matches,
`self_dir` stays empty, both local branches are guarded by `[ -n "$self_dir" ]`, and it correctly
falls through to the network. Don't "fix" that guard.

### JSON without jq or python

`parse_json_file` shells out to JXA (`osascript -l JavaScript`) — the JavaScriptCore parser on every
macOS. This is why the tool has no dependencies beyond curl and bash.

It emits a flat line protocol delimited by **US (`\x1f`)**, not tab. US is not an IFS-whitespace
character, so bash `read` preserves *empty* fields — an omitted `icon` must not shift every later
column. Keep that invariant if you touch the protocol; the record layouts are documented in the
comment block above the function.

### The category model is parallel arrays

macOS ships bash 3.2 (the last GPLv2 release), which has **no associative arrays**. State lives in
index-aligned arrays — `CAT_ICON`, `CAT_NAME`, `CAT_METHOD`, `CAT_PATHS`, `CAT_KB`, `CAT_SEL`, … —
all appended through `add_category`, with `N` as the count. `CAT_PMETHOD` is aligned line-for-line
with `CAT_PATHS` for `project` categories, where one repo mixes `rm`'d build dirs with `trash`'d
git-ignored files.

Bash 3.2 is the compatibility floor for everything here. Don't reach for `declare -A`, `${var^^}`,
or `mapfile`.

### Sizing goes through files, not variables

`compute_sizes_write` `du`s categories in concurrent subshells — which cannot mutate the parent's
arrays — so each writes `$SCAN_DIR/size_$i`, and `compute_sizes_read` loads them back in the parent.
Keep that split; assigning `CAT_KB` inside the subshell silently does nothing.

### Safety is enforced below the rules, not by them

`is_safe_target` gates every deletion and no rule can opt out of it. It rejects `/`, `$HOME` itself,
relative paths, anything containing `..`, and the protected set (`~/Documents`, `~/Desktop`,
`~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`, `~/.ssh`, `~/.gnupg`, iCloud Drive). It then
requires **both** lexical containment under `$HOME` *and* physical containment — resolving the
parent with `cd -P` so a symlinked component can't walk a delete off the home tree.

This function is the tool's entire trust story. Treat changes to it as high-risk.

### Keypresses come from fd 3, never fd 0

Under `curl … | bash`, fd 0 *is the script* and bash is still reading it. Redirecting fd 0 would eat
the rest of the program and break the pipe. The script opens `/dev/tty` on fd 3, falls back to fd 0
only when it's a terminal, and otherwise uses `/dev/null` so reads hit EOF (treated as "no answer")
instead of consuming the script as keystrokes. Every interactive read uses `<&3`.

### Performance landmine in `register_paths`

Glob expansion deliberately uses bash's own pathname expansion with `IFS` emptied, rather than
`compgen`/process substitution. A full rules set is ~250 patterns, and a fork per pattern made bash
3.2 stop making progress — the scan hung for minutes. The empty `IFS` keeps unquoted `$pat` globbing
without word-splitting, which matters because real patterns contain spaces
(`~/Library/Application Support/*/Code Cache`).

## Release / CI

`.github/workflows/release.yml` fires on pushes to `main` that touch `cdm` or `rules/**` (docs-only
changes correctly cut no release). It runs `bash -n cdm` **before** publishing — the asset is piped
straight into a user's shell, so a syntax-broken script must never become `latest`.

Tags are `vYYYY.MM.DD.N`, where `N` is claimed by scanning for the lowest unused ordinal for the
day, so repeat pushes and re-runs can't collide.

The release asset must stay named exactly `cdm` — `/releases/latest/download/cdm` resolves by asset
name, and the README's downloads badge counts fetches of that asset.

## Conventions

- Rules are fetched from raw `main` at runtime, so a rules change is live for piped users the moment
  it merges — before any release. Landing-page and README claims about what `cdm` cleans must track
  `rules/`.
- The tool makes **no network calls** other than fetching its own rule JSON. There is no telemetry
  and no phone-home; the donate URL is a string it prints. Keep it that way.
- The donate line appears only in `--help` and once after a clean that actually freed something —
  never on a scan or a dry run.
- Every run appends to `~/.cleandevmac/clean.log`.
- The landing page lives in a separate repo (`cleandevmac/cleandevmac.github.io`) and hardcodes the
  run command, the rule schema, and the TUI keybindings. Changing any of those here means updating
  it there.
- Nothing "installs" `cdm` — the pipe runs it and leaves nothing behind. Only the optional
  save-to-`PATH` recipe in the README puts a file on disk, and that section is the only place the
  word *install* belongs.
