# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

CleanDevMac (`cdm`) is a single ~1700-line bash script that reclaims disk space on macOS from
developer caches, build artifacts, per-repo project junk, Docker/Podman, and orphaned app data.
`cdm` is the whole program — `rules/*.json` is its data. There is no build step and no dependency
manifest. Tests live in `tests/` and are plain bash with no framework behind them (see Commands).

`docs/DESIGN.md` holds the *why*. `cdm` itself carries the code and a one-line summary per
function, and points at the design notes with `# see docs/DESIGN.md#<anchor>` — the script is
what gets piped into a user's shell, so it stays readable as a program. Rationale that runs to a
paragraph belongs in the design notes, at the anchor the code already points to; do not grow it
back into `cdm`.

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

Exercising a single unit: source the script without running it. The test hook near the bottom of
`cdm` returns early when `CDM_LIB=1`, so functions load into your shell with no scan and no TUI.

```bash
CDM_LIB=1 . ./cdm
SCAN_DIR=$(mktemp -d)        # most functions need this set
resolve_patterns && ls "$PATTERNS_DIR"
is_safe_target "$HOME/Documents" && echo REACHABLE || echo "correctly refused"
```

### Tests

```bash
./tests/run.sh               # the whole suite, ~4s
./tests/run.sh safe_target   # only files matching a substring
./tests/mutate.sh            # break cdm on purpose; the suite must notice
```

`tests/lib.sh` is that same `CDM_LIB` hook with a sandboxed `$HOME` wrapped around it, plus three
assertions (`assert_eq`, `assert_ok`, `assert_fail`) and `in_locale`, which runs one command under a
locale the suite names rather than the developer's. No framework, for the same reason there are no
dependencies: a suite needing `bats` installed would be testing a machine no user has. Each file
runs under `/bin/bash` — 3.2, the floor — in its own process.

Two ordering constraints are load-bearing and documented at length in `lib.sh`: `$HOME` must be
exported *before* `cdm` is sourced (it snapshots `HOME_P` at source time, and `is_safe_target`
compares against that), and the cleanup trap must be armed *before* the source and again *after*
(cdm installs its own `EXIT` trap, clobbering yours).

`tests/mutate.sh` is the part that matters. A passing suite proves nothing on its own — an assertion
that cannot fail reads exactly like coverage — so each mutation breaks cdm one edit at a time and
requires the named test file to fail. It rejects mutations that stop matching (a stale pattern would
otherwise "pass" forever while testing nothing) and ones that break the parse rather than behavior.
Adding a test without adding its mutation is half the job.

Note that not every mutation is catchable. `is_safe_target`'s early guards are redundant with its
lexical + physical containment pair, so deleting one changes no observable behavior — those are
*equivalent mutants*, and `mutate.sh` documents why they are deliberately absent rather than listing
holes the tests can never close.

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

### The terminal *size* also comes from fd 3

Same reason, and it is easy to get wrong because the wrong version fails silently rather than
loudly. `term_rows`/`term_cols` run `stty size <&3`. Not fd 0 — piped, that is the script, so `stty`
just errors. And the `tput lines/cols` fallback cannot cover for it: tput sizes its *output* fd,
and both callers run inside `$(...)` where fd 1 is a pipe, so tput answers from static terminfo —
a plausible-looking **24x80**. `$LINES`/`$COLUMNS` are empty too, since bash only maintains them
when interactive. So every piped run — i.e. very nearly every run — laid out at 24x80 and ignored
the rest of the window, on every terminal, for everyone.

Two lessons worth keeping: any "what size is my terminal" fallback chain that ends in a *constant*
will look like it works, so test it in a real pty at a non-default size; and a 24x80 assumption is
not merely wasteful on a big window — on a window **shorter than 24 rows** the frame overflows and
the terminal scrolls on every repaint, which is what stacked copies of the menu in the scrollback.

### Measure text in display columns, never in characters or bytes

Three different numbers, and the layout only ever wants the third:

- `${#s}` counts **characters** — but only under a UTF-8 `LC_CTYPE`, which is why `cdm` pins one at
  the top. Under a C locale it counts **bytes** and `${s:0:n}` will slice a multibyte character in
  half; every rule `desc` has an em dash in it, so that was a visible mojibake bug for anyone
  arriving without a `LANG` (plain ssh, launchd, Terminal with the locale box unchecked).
- `printf '%-36s'` pads to **bytes**, so it silently short-changes any non-ASCII name — `Tiếng-Việt`
  is 10 characters but 14 bytes and got *no* padding at all. The row builder pads by hand instead.
- `dwidth` gives **display columns**, the only unit the terminal lays out in. CJK, Kana, Hangul and
  emoji are two columns each. It classifies on the UTF-8 lead byte (`>= 0xE3` is wide), which keeps
  Latin/Vietnamese/Greek/Cyrillic correctly at one, and takes a fast path (via `is_ascii`) on
  pure-ASCII strings so the common case costs nothing. `clip_plain`, `shorten_left` and the
  name-column budget all go through it — mixing units there means a row renders wider than it was
  budgeted, wraps, and scrolls the frame on every repaint.

### A bracket range is not the guard you think you wrote

Ranges in bash patterns are resolved by **`LC_COLLATE`**, and `cdm` pins only `LC_CTYPE`. Those
three fast paths above were guarded with `*[!\ -~]*` — which reads as "contains a non-ASCII
character" and is not. Under any locale but `C`/`POSIX` — **284 of the 288** a stock macOS installs,
including every one a Terminal exports — the letters and digits collate *above* `~`, so ` ` through
`~` is a punctuation-only interval: the guard answered "not ASCII" for `abc`, and every fast path
was dead code for very nearly every user, for the life of the tool.

Two lessons, both general:

- Write the guard as a character **class** — `[[:ascii:]]` is `LC_CTYPE`-based, which `cdm` pins, so
  it cannot regress this way. (`[[:print:]]` is not a substitute: it takes the fast path for CJK.)
  `looks_like_bundle_id` had the same trap and is fixed too — but note the class alone was *not* the
  fix there. The pin forces a **UTF-8** ctype, under which `[[:alnum:]]` means "any alphanumeric in
  Unicode", so `*[![:alnum:]._-]*` would have traded a locale-dependent orphan list for a uniformly
  wider one — offering a folder named `私の.大切な.データ` for deletion. It composes `is_ascii` with
  the class instead. A class fixes *which* locale category decides; it does not by itself say ASCII.
  See `docs/DESIGN.md#bundle-id-shape`.
- It hid because it failed **open**, into a slower path that was correct. No output was ever wrong —
  it just did far more work on the strings the fast path exists to make cheap (measured: 200
  `dwidth` calls on a 42-column path, 0.55s before / 0.01s after), and *no assertion about output
  can see that*. `tests/mutate.sh` is what surfaced it: a mutation inside the dead
  branch survived, because a mutation in unreachable code cannot fail a test. Treat a surviving
  mutation as a claim about reachability, not only about coverage. `tests/test_text_width.sh` now
  pins the locale itself (`in_locale`, in `tests/lib.sh`) rather than trusting the developer's —
  under `LANG=C.UTF-8` the suite passed and CI, on `en_US.UTF-8`, did not.

### A locale-sensitive test must pin its own locale — and CI sweeps the rest

Two of these have now shipped: the collation range above, and `human_kb` formatting `1,00 GB`
through awk's `%f` under a European locale (see `docs/DESIGN.md#numeric-format`). The second is the
instructive one, because the suite **already caught it** — `LANG=de_DE.UTF-8 ./tests/test_helpers.sh`
failed on unmodified `main` — and nobody ever ran it that way. A suite is worth one locale's coverage
unless it says otherwise, however many assertions it has.

Both halves of the answer are load-bearing, and they cover different things:

- Tests that know they are locale-sensitive pin their own with `in_locale` (`tests/lib.sh`),
  plus a **premise assertion** that the hostile locale really is hostile — bash and awk fall back to
  C *silently* on an unknown locale, so `de_DE.UTF-8` failing to resolve would make every row pass
  under C and prove nothing. This is the deterministic, mutation-backed half.
- `.github/workflows/tests.yml` runs the whole suite under five locales anyway, because pinning only
  ever covers hazards someone anticipated. At ~4s a pass it is the cheapest coverage in the file.

Read `in_locale`'s comment before using it. It has to **export** (a forked `awk`/`sort` reads the
locale from its environment, and a bare assignment is not in it), by **assignment inside `( )`** (the
`LC_ALL=x func` prefix form does not re-init the locale in bash 3.2). Get either wrong and the test
passes against the *unfixed* code — which is the exact failure being defended against, so verify a
new locale test actually fails before trusting it.

### The menu is a fixed-height frame — mind the last newline

`render_menu` emits exactly `rows` lines when the list overflows, and the last one deliberately
carries **no trailing newline**: a newline on the bottom row scrolls the screen, which would drag
the title off the top on every frame. It repaints with `\033[H` … `\033[J` and each line ends in
`$K` — deliberately *not* `\033[2J`, which on Terminal.app/iTerm2 scrolls the outgoing frame
into the scrollback instead of discarding it. The menu draws on the alternate screen
(`\033[?1049h`), and `leave_tui` restores; anything printed after `leave_tui` survives the run,
anything before it dies with the alternate screen — so parting messages come after.

### The frame is data, not a format string

`$buf` is built from the `ESC`/`K`/`NL` **literals** defined under the colour block, and emitted
with `printf '%s' "$buf"`. Never `printf "$buf"`, and never rebuild it from escape *text* like
`"\033[K\n"` — the frame is assembled out of category names and repo paths, and bash's printf reads
backslashes in a format string. A directory legitimately named `ha\nck` then emits a real newline
(the frame outgrows `rows` and the terminal scrolls on every repaint) and one named `esc\033[41m`
injects raw escape sequences from a filename. `%` needs no escaping for the same reason, which is
why the old `${line//%/%%}` dance is gone. Row text goes through `printf` as *arguments*, which is
always safe; the two bare `printf '\033[H'` / `'\033[J'` calls are constant formats with no data.

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

- Long rationale lives in `docs/DESIGN.md`, never in `cdm`. Each site in the script keeps a one-line
  summary and a `# see docs/DESIGN.md#<anchor>` pointer. When you change one of those decisions,
  update the anchored section — a design note that no longer describes the code is worse than none.
- Cite code by **name**, not by line number. `cdm:1484` was the old habit and every one of those
  citations rotted: they were 38–90 lines stale before anyone noticed, because nothing verifies a
  number in a comment. Say `is_safe_target()` instead — it survives every edit above it.
- Rules are fetched from raw `main` at runtime, so a rules change is live for piped users the moment
  it merges — before any release. Landing-page and README claims about what `cdm` cleans must track
  `rules/`.
- The tool makes **no network calls** other than fetching its own rule JSON. There is no telemetry
  and no phone-home; the donate URL is a string it prints. Keep it that way.
- The donate line appears only in `--help` and once after a clean that actually freed something —
  never on a scan or a dry run.
- Every clean appends a receipt to `~/.cleandevmac/clean.log`; a scan or a `--dry-run` never writes
  to it. `rotate_log` caps it at 1 MiB, keeping the newest 256 KiB — the tool that reclaims disk has
  no business being the thing quietly consuming it. Same reasoning behind `sweep_stale_scan_dirs`:
  `cleanup_on_exit` removes this run's `SCAN_DIR`, but no `EXIT` trap runs when the process is
  killed outright (SIGKILL, or SIGHUP when the terminal closes), so each run also sweeps the
  `$TMPDIR/cdm.XXXXXX` dirs stranded by earlier ones. That sweep is the one `rm` that does not pass
  `is_safe_target` — it cannot, since `$TMPDIR` is not under `$HOME` — so its fixed-width glob over
  cdm's own mktemp template *is* the safety boundary. Nothing rule-derived reaches it. Widen that
  glob and `tests/test_scan_dir_sweep.sh` fails.
- The landing page lives in a separate repo (`cleandevmac/cleandevmac.github.io`) and hardcodes the
  run command, the rule schema, and the TUI keybindings. Changing any of those here means updating
  it there.
- Nothing "installs" `cdm` — the pipe runs it and leaves nothing behind. Only the optional
  save-to-`PATH` recipe in the README puts a file on disk, and that section is the only place the
  word *install* belongs.
