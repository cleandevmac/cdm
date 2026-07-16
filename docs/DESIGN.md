# cdm — design notes

Why `cdm` is written the way it is. `cdm` itself holds the code and a one-line
summary per function; the reasoning lives here, so the script that gets piped
into a user's shell stays readable as a program.

Each section is linked from the corresponding site in `cdm` as
`see docs/DESIGN.md#<anchor>`. Ordered as the code is, top to bottom.

This file is not a tutorial and not an API reference — it is the record of the
non-obvious constraints, and of the bugs that established them. If you are about
to "simplify" something in `cdm` that looks convoluted, look for it here first.

<a id="what-cdm-is"></a>
## What cdm is

CleanDevMac (cdm) — https://cleandevmac.github.io
Interactive macOS cleanup for developer caches, build artifacts, temp data,
leftover data from uninstalled apps, and regenerable folders in your code repos.

What it does:
  1. Reclaims space from regenerable caches / build output (Xcode, Go, Node,
     Gradle, Maven, Cargo, Python, Homebrew, Electron & browser caches, ...).
  2. Clears project junk in your repos (node_modules, dist, build, target,
     __pycache__, or anything your .gitignore ignores).
  3. Surfaces leftover data from apps that are no longer installed.

Everything it can clean is described by JSON "rule" files (see the rules/
directory of the cleandevmac/cdm repo). The tool reads them from a local
folder, or downloads them, so it also runs standalone:

  curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm | bash

Nothing is deleted without an itemized confirmation. Caches / build output are
removed permanently (they regenerate); orphaned app data and git-ignored files
are moved to the Trash so they can be restored. --dry-run only looks.

<a id="frame-literals"></a>
## The frame is built from literals, not escape text

Control sequences the menu's own layout is built from. Unlike the colours they sit
beside in `cdm`, these are structural, not decoration — `--no-color` must never
blank them — so they live outside that branch.

They are LITERAL characters, not the escape *text* "\033[K". The menu frame is
assembled out of category names and repo paths, and `printf "$frame"` would read
that data as a format string: a directory legitimately named `ha\nck` would emit
a real newline (pushing the frame past the bottom of the screen, so it scrolls on
every repaint) and one named `esc\033[41m` would inject raw escape sequences into
the terminal. Building the frame from literals lets render_menu print it with
`printf '%s'`, where a name is only ever data.

<a id="locale-pin"></a>
## The LC_CTYPE pin

Pin a UTF-8 ctype for this script's own string math. bash 3.2 makes ${#s} and
${s:0:n} count BYTES rather than characters unless LC_CTYPE says UTF-8 — and
piped from curl the locale is whatever the user's shell happened to export,
which is nothing at all over plain ssh, from launchd/cron, or with Terminal's
"Set locale environment variables on startup" unchecked. The whole TUI measures
and slices text with those two operators, so under a C ctype every rule's
description gets cut mid-em-dash into a replacement glyph and the keys line
mis-measures itself. Only LC_CTYPE is set: collation stays the user's business,
and the commands that need a locale of their own — the `LC_ALL=C sort` calls that
want byte order, the `LC_ALL=C awk` calls that format sizes — still say so
per-command. See #numeric-format for why that one stayed per-command too.

<a id="numeric-format"></a>
## Sizes are formatted under LC_ALL=C, per command

human_kb formats with awk's `printf "%.2f GB"`, and `%f` writes whichever decimal
separator LC_NUMERIC names. Under a European locale that is a comma, so the menu
rendered `1,00 GB` — in a UI that is otherwise English throughout. That is the
argument for pinning rather than localizing: cdm is not translated. The label
beside that number says "Reclaimable", the receipt it lands in is English, and
every other number the tool prints is an integer with no separator at all. A
comma there is not a translation, it is the single localized glyph in an English
sentence — and it would make the format of `~/.cleandevmac/clean.log` depend on
which shell happened to launch the run. Localizing the UI is a real project; it
does not start with the decimal point.

Two things about *how* it is pinned, both load-bearing:

- **LC_ALL, not LC_NUMERIC**, because LC_NUMERIC loses to it. LC_ALL outranks
  every other LC_* in the process that reads it, so `LC_NUMERIC=C awk` still
  prints `1,50` for anyone who exports `LC_ALL=de_DE.UTF-8` outright. That same
  precedence is what sinks the top-level version of this fix: the LC_CTYPE pin
  above deliberately leaves an exported LC_ALL alone when it already names a
  UTF-8 locale, so an exported `LC_NUMERIC=C` sitting beside it would be dead on
  arrival. Making a top-level LC_NUMERIC pin actually bite would mean
  neutralizing LC_ALL — re-expanding it into the individual categories, to
  preserve the collation the pin promises to leave the user — which is a lot of
  machinery to buy a decimal point.
- **Per-command**, because that is already the convention (`LC_ALL=C sort`), and
  it leaves the pin's stance where it was: cdm sets one category for its own
  string math, and anything needing a fixed locale asks at the call site.

Only human_kb needs it. human_to_kb's awk is deliberately left bare: its `%d`
emits no separator, and the number it parses (`1.8`) is interpolated into the awk
*source*, where the decimal point is a period regardless of locale. Guarding it
would add a line that no test could ever fail.

bash's own printf is not an escape hatch either — it reads `%f` through the same
LC_NUMERIC, and worse, under de_DE it cannot even parse `1.5` as *input*
(`printf: 1.5: invalid number`); it wants `1,5`.

<a id="fd-3"></a>
## Keypresses come from fd 3, never fd 0

Keypresses are read from fd 3, never fd 0. Under `curl … | bash` fd 0 is the
script itself and bash is still reading the remaining lines from it, so
redirecting fd 0 would both steal the rest of the script and break the pipe
(curl: "Failure writing output to destination"). Probe in a subshell so a
missing/unusable /dev/tty produces no error and no permanent redirection.

<a id="log-cap"></a>
## Why clean.log is capped

The receipt of every clean ever run is appended to one file, so it only grows.
A disk-cleanup tool has no business being the thing quietly eating the disk —
cap it, keeping the most recent entries, which are the ones anyone ever reads
("what did it delete just now?"). Rotation happens at the single point of
write, in run_cleanup; a scan or a --dry-run never touches the log at all.

<a id="alternate-screen"></a>
## enter_tui / leave_tui and the alternate screen

enter_tui / leave_tui — move the menu on and off the alternate screen.

The split matters for more than tidiness. The alternate screen has no
scrollback, so anything written there is gone the moment we leave it: only the
menu — which repaints itself from scratch anyway — belongs on it. The two
scrolling *reports* (the cleanup receipt and the details view) are written on
the normal screen, where they land in the user's terminal history and survive
the run. That is also why every parting message comes after a leave_tui.

Both are idempotent, so the EXIT trap can't double-restore a run that already
left, and the CLEAN path can leave once and rely on the N==0 exits leaving again.

<a id="sweep-stale-scan-dirs"></a>
## sweep_stale_scan_dirs

sweep_stale_scan_dirs — remove the SCAN_DIRs that earlier runs stranded.

cleanup_on_exit removes this run's, but no EXIT trap can run if the process is
killed outright, so a killed run leaves an empty cdm.XXXXXX behind forever and
they accumulate. A disk-cleanup tool quietly littering /var/folders is not a
joke that stays funny, so each run tidies up after the ones before it.

This is the one rm in the script that does NOT go through is_safe_target, and
it cannot: that gate demands containment under $HOME, while these live in
$TMPDIR by construction. What replaces it is that the target is neither user
data nor pattern-derived — the glob is this script's own mktemp template,
literal and fixed-width, so it matches only directories cdm itself created.
Nothing read from a rules file reaches this.

<a id="json-line-protocol"></a>
## The JSON line protocol

---------------------------------------------------------------------------
JSON parsing (JXA — the JavaScriptCore parser shipped with every macOS; no
jq / python required). Emits a flat line protocol whose fields are separated
by US (\x1f, "\037"), NOT tab: US is not an IFS-whitespace character, so bash
`read` preserves EMPTY fields (an omitted icon must not shift the columns).
Records are newline-separated. Field layout per record type:
  SR<US>root | SPRUNE<US>name | SDEPTH<US>n | SREPOS<US>n           (scan config)
  C<US>kind<US>icon<US>name<US>method<US>default<US>desc            (category)
  P<US>path | D<US>dirname                                         (paths / dirs)
  L<US>path<US>strip | SKIP<US>prefix | SHARED<US>id                (orphan config)
  FILE<US>name | ORPHAN<US>name | ERR<US>message
---------------------------------------------------------------------------

<a id="glob-expansion"></a>
## Glob expansion in register_paths

Expand the pattern with bash's own pathname expansion instead of
`< <(compgen -G "$pat")`. The process substitution cost a fork per
pattern, and a full rules set is ~250 of them: past roughly 250
bash 3.2 stops making progress entirely and the scan hangs for
minutes instead of finishing in seconds.

IFS is emptied so the unquoted $pat still globs but does NOT
word-split — patterns like "~/Library/Application Support/*/Code
Cache" contain spaces, and splitting them matches nothing at all.
An unmatched glob expands to itself, which the -e test discards.

<a id="project-scanning"></a>
## Project-junk scanning

---------------------------------------------------------------------------
Project-junk scanning (node_modules, dist, build, target, git-ignored, ...)

Junk is grouped BY PROJECT — one category per git repository — so you can pick
exactly which projects to clean and see what each holds. Junk that isn't inside
a repo is skipped (it's almost always a tool/language cache the cache rules
already cover, not one of your projects). Within a project every item keeps its
own method: known regenerable build/dependency dirs are deleted (they rebuild),
while any other git-ignored entry (local .env, config, logs) is moved to the
Trash so it can be recovered.

The helpers in this part of the script (classify_method / project_key /
shorten_left / flush_project_category) are only ever called from scan_projects and
read its locals through bash dynamic scope — the same pattern parse_pattern_stream and
flush_pattern_category use.
---------------------------------------------------------------------------

<a id="project-key"></a>
## project_key

project_key <path> — echo the nearest enclosing git repo root (longest match
wins; REPO_ROOTS is sorted longest first), or EMPTY when the path is not inside
any repo. A "project" is a git repo: junk that isn't in one is almost always a
tool/language cache (Go stdlib, global npm, cargo/npx cache, editor
extensions), which the cache categories already handle and which must not be
swept up here — so callers skip a path with no key.

<a id="shorten-left-fast-path"></a>
## shorten_left's fast path and the ${s: -0} trap

Fast path: no wide characters possible, so columns == characters. The tail
is taken by counting an offset from the LEFT, and not with the obvious
${s: -$((max - 1))}: at max 1 that reads ${s: -0}, and -0 is not negative,
so bash takes it as offset 0 — the whole string — and hands back '…abcdef'
for a one-column budget. The branch needs ${#s} > max to be reached, so the
offset is always >= 2 and never runs off either end.

<a id="find-pass"></a>
## The single find pass

One find pass per root captures BOTH repo roots (a .git DIRECTORY — needed
to group junk by project even when git-ignored scanning is off) AND
regenerable target dirs, while pruning heavy/irrelevant trees. Only a real
.git folder counts as a project root: a bare ".git" file (git worktrees /
submodules) is intentionally ignored, so a folder is a "project" only when
it directly contains a .git directory. .git is captured in its own branch
(not the prune list) so we learn the repo but never descend it.

<a id="dedup-nesting"></a>
## De-duplicating nested items

De-duplicate and drop any item nested under another kept item (a git-ignored
file inside a dir we already delete) — sorting by path puts an ancestor
immediately before its descendants, so a single prefix test suffices; this
also keeps the per-project size total from double-counting. Then group by
project key for stable, contiguous per-project categories.

<a id="sort-by-size"></a>
## sort_by_size

sort_by_size — order the menu biggest-first, so the rows worth the most disk
are the ones you land on. Sorts an index list through `sort` rather than in
the shell: bash 3.2 (what macOS ships) has no associative arrays, and the
ties matter — `sort -s` keeps equal-sized rows in their rules-file order, so
the grouping the JSON authors chose survives.
Must run after compute_sizes; re-run after anything that changes CAT_KB.

<a id="terminal-size"></a>
## Terminal size comes from fd 3 too

Terminal size. Ask fd 3 — the one handle on the terminal this script is
guaranteed to hold — and never fd 0: under `curl … | bash` fd 0 is the *script*,
so `stty size` there fails outright. The tput fallback cannot cover for that,
because tput sizes its *output* fd and both callers run inside $(...),
where fd 1 is a pipe — so tput answers from static terminfo (24x80) rather than
from the window. $LINES/$COLUMNS are empty too (bash only maintains them when
interactive). All three together silently pinned every piped run — which is
very nearly every run — to a 24x80 layout, ignoring the rest of the window.
The tput/$LINES/constant tail stays on for the no-tty case, where fd 3 is
/dev/null and `stty size <&3` correctly reports nothing.

<a id="display-columns"></a>
## Display columns, _cw and is_ascii

Display columns, which are not the same thing as characters: an East Asian Wide
character (CJK, Kana, Hangul, fullwidth forms) and an emoji each take TWO. The
layout budgets rows in columns, so measuring in characters would let a
repo path under ~/プロジェクト render wider than its row was sized for — it
wraps, the frame grows past `rows`, and the screen scrolls on every repaint.

Classify by UTF-8 lead byte, which printf hands back as a signed char: 0xE3 (227)
is where U+3000 and up begins — CJK/Kana/Hangul, and 0xF0 for emoji — so >= 227
is two columns and anything below is one. That deliberately leaves Latin,
Vietnamese, Greek and Cyrillic on the one-column side, which is correct for them.
Known gap: a handful of U+2xxx symbols (⚡ ☕ ⛅) measure 1 but render 2. They only
ever appear as rule icons, which sit in an unpadded column of their own, so every
row shifts alike and nothing misaligns.

is_ascii <text> — true when every character is ASCII, so no character can be
wide and columns == characters. shorten_left, dwidth and clip_plain hang their
fast paths on it.

It must be a character CLASS and never a bracket range, which is the shape this
was first written in and the bug that shipped: a range is resolved by
LC_COLLATE, and cdm pins only LC_CTYPE (see the top of the file). Under any
locale but C/POSIX — 284 of the 288 installed on a stock macOS — the letters
and digits collate *above* `~`, so ' ' through '~' is a punctuation-only
interval and `*[!\ -~]*` answered "not ASCII" for `abc`. All three fast paths
were unreachable for very nearly every user. It hid because it failed *open*,
into a slower path that is correct: no wrong output, just many times the work
on the very strings the fast path exists to make cheap, and no assertion about
output can see that. [[:ascii:]] is LC_CTYPE-based and cannot regress that way.
[[:print:]] is not a substitute — it takes the fast path for CJK.

<a id="k-add"></a>
## _k_add

_k_add <cap> <label> — append one "KEY label" pair to the line being built by
build_keys_line. Writes both forms in lockstep: _S is styled, _P is a plain
shadow of the same display width, since _S is unmeasurable (its escapes carry
no columns). A cap is ${#cap}+2 wide in BOTH modes — reverse video pads with a
space either side, --no-color brackets it — so _P's " cap " matches each.

<a id="keys-line"></a>
## build_keys_line

build_keys_line <cols> — build the shortcut hint line to fit <cols> on ONE
physical line. Sets _S (styled, ready to print) and _P (plain, for measuring).

This line cannot be clip_plain'd like the item rows and the description: its
right edge holds `q quit`, the one key a user must never lose. So it degrades
by tier instead of by truncation, shedding first the labels whose key already
implies them (↑↓ move, Enter details), then the rest. Widths are mode-
independent, so --no-color picks the same tier.
  1: everything spelled out          95 cols (81 under --dry-run)
  2: self-evident labels dropped     76 cols (64)
  3: caps only                       44 cols (38)

<a id="menu-chrome"></a>
## The menu's fixed chrome

Chrome is title, status, keys, ↑-scroll, ↓-scroll, description; every other
terminal row goes to the item list. Item rows and the description are clipped
to the terminal width and the keys line is tier-fitted to it, so each
is one physical line and this count is exact — the list fills the screen, and
the frame is exactly `rows` lines tall (the last one unterminated; see the
newline strip at the end).
keys_h is measured rather than assumed to be 1: below ~44 columns even the
narrowest tier wraps, and the list must still not overrun the screen.

<a id="short-windows"></a>
## Short windows shed chrome

A window too short to seat the full chrome *and* a usable list sheds the
optional chrome — the description first, then the two scroll indicators —
rather than emit a frame taller than the screen. Overrunning would scroll
the terminal on every repaint, which is far worse than a missing hint line:
it stacks a copy of the menu into the scrollback each time. Reachable now
that the real window size is honoured; a tmux split can be a few rows tall.

<a id="scroll-clamp"></a>
## Clamping SCROLL to the last page

Clamp to the last page. Every correction before it only pulls SCROLL toward the
cursor; none bounds it by the list's end. When the window *grows*, viewport
grows with it, and a SCROLL left over from the smaller window would strand
the list partway down — a few rows under a bogus "↑ N more above", with the
rest of the window blank.

<a id="name-column"></a>
## The name column's width

Name column width. The fixed furniture around it — cursor, box, icon, size
and the gaps — is 20 display cols, so a row measures 20 + name_w and the
summary that follows takes what's left. Size the column to the longest name
rather than to a constant, so a wide window spends its columns showing whole
project paths instead of padding. Clamped so the summary keeps a usable
share and a narrow window still fits. Forks nothing; this runs every frame.
Measured in display columns, not characters — the clippers honour the
same unit, so the row is exactly as wide as it was budgeted no matter what
script the names are written in.

<a id="padding"></a>
## Why padding is done by hand

One run of blanks, sliced per row to pad the name column. printf's own
`%-Ns` pads to N *bytes*, not characters, so it short-changes every name
carrying a non-ASCII byte — a repo path with diacritics ("Tiếng-Việt" is 10
characters but 14 bytes) gets no padding at all and drags the size column
left. Built once per frame rather than per row; no forks either way.

<a id="name-clipping"></a>
## Which end a name clips from

Clip the name to the name column so a long name can't push the line wide.
Project rows are named by path, where the tail — the repo itself — is
what identifies the row and the leading directories are the expendable
part, so those clip from the left. Every other name is a label, and
clips from the right.

<a id="last-newline"></a>
## The frame's last newline

Drop the frame's final newline. That line sits on the terminal's bottom row,
and a newline *there* scrolls the whole screen up one — dragging the title
off the top on every single frame. (Invisible until the size was honoured,
since a 24-line frame never reached the bottom of a real window.) Stripped
here rather than special-cased at each emission, because which line lands
last depends on how much chrome the window was tall enough to keep.

<a id="repaint"></a>
## Repainting in place

Repaint in place: home, overwrite every line (each already ends in $K, which
clears its tail), then erase-below to wipe whatever a shorter frame left
behind. Deliberately not \033[2J: erasing the *display* scrolls the outgoing
frame into the scrollback on Terminal.app and iTerm2, so every redraw stacked
another copy of the menu up there — and resizing the window reflowed the
whole pile back into view.

'%s', never printf "$buf": the frame contains repo paths, and as a format
string a directory named `ha\nck` or `esc\033[41m` would inject newlines and
escape sequences of its own. These two are constant formats with no data.

<a id="wait-any-key"></a>
## wait_any_key

wait_any_key — block until a real keypress. On shells whose read returns when
a trapped SIGWINCH (terminal resize) fires, that wake carries no key; absorb it
so a resize never dismisses a "press any key" prompt. (On bash 3.2 read simply
restarts, so this just blocks until a key — same intended effect.) Stops on a
real key or on stdin EOF.

<a id="rotate-log"></a>
## rotate_log

rotate_log — cap clean.log, keeping the newest LOG_KEEP_BYTES.

Deliberately truncate-in-place rather than clean.log.1 + clean.log.2: a
rotation scheme that keeps N generations still grows without bound in the
only dimension that matters here (total bytes on disk), which is the thing
this exists to stop. One file, one ceiling.

<a id="resize-redraw"></a>
## Redraw on resize

---- Interactive menu ------------------------------------------------------
Redraw on terminal resize. A SIGWINCH sets NEED_REDRAW; the read polls
with a 1s timeout because bash 3.2's read does NOT return early when a signal
fires (it restarts) — so we can't rely on the trap interrupting the read and
instead wake at least once a second to act on the flag. To avoid flicker the
menu is re-rendered only when something changed ($dirty): a keypress or resize.
