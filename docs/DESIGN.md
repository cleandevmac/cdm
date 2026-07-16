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
and the `LC_ALL=C sort` calls that need byte order still say so per-command —
including every `sort -u`, for the reason below.

<a id="sort-u-collation"></a>
## `sort -u` compares by collation, not by bytes

`sort -u` drops a line that compares equal to the line before it, and "equal"
means strcoll, not memcmp. The ctype pin above deliberately leaves LC_COLLATE to
the user, so an unpinned `sort -u` lets the user's environment decide which of
cdm's own lines to discard. Four sites did. Measured on macOS (BSD sort):

    printf 'cafe\xcc\x81\ncafe\xcc\x80\ncafe\xcc\x88\n' | sort -u   # en_US.UTF-8 -> 1 line
    printf 'cafe\xcc\x81\ncafe\xcc\x80\ncafe\xcc\x88\n' | LC_ALL=C sort -u        # -> 3 lines

Those are café, cafè and cafë spelled NFD — an ASCII base plus a combining mark.
Three different names; two silently stop existing. NFD is not a curiosity: it is
what git returns with `core.precomposeunicode=false`, and what arrives from
Linux-authored repos, rsync and zip archives. Nothing has to normalise anything.

The mechanism is worth stating precisely, because the two obvious readings are
both false and each mis-states the blast radius in a different direction. It is
**not** truncation at the first uncollatable character — `ab<SHY>c` and
`ab<SHY>d` stay distinct. It is **not** "an identical ASCII skeleton collapses"
— `abc` and `ab<SHY>c` stay distinct too. What actually happens: every character
missing from the locale's collation table collates as one shared weight, so two
uncollatable characters are indistinguishable **from each other**, and never
from a plain ASCII line. Hence `ab<SHY>c` == `ab<ZWSP>c`, while `abc` matches
neither. The uncollatable set is not exotic — the combining marks, NBSP, U+2010
and the zero-width family are all in it.

All four sites take `LC_ALL=C` rather than only the ones where loss is provably
reachable, because -u's contract is de-duplication and byte-distinct lines are
not duplicates:

* `flush_project_category`'s summary — real filenames, so non-ASCII is routine.
  A collapse drops a name from the "what's inside" blurb, whose entire job is to
  say what is in there. This is the one site with a user-visible **ordering**,
  the only argument for keeping the user's collation; it loses, because the
  blurb is a junk-name list nobody navigates and byte order is what the rest of
  cdm already sorts by. It is also the only site reachable as a unit test, and
  so the only one whose pin is proven by behaviour rather than by inspection.
* `scan_projects`' uniq_names — feeds `find -name`, so a dropped name is a
  directory never scanned. Every shipped rule is ASCII today, but rules are data
  and adding a target is meant to be a JSON edit.
* `build_installed_set`'s INSTALLED list — `defaults read` returns arbitrary text, so
  non-ASCII reaches it and lines really can be dropped. See below.
* `register_orphans`' bid list — a dropped bid loses its whole orphan group.

INSTALLED earns its own note, because a line lost there is the only one that
could delete a **live app's** data: `bid_is_kept`'s `grep -qxF "$bid"` is what
answers "this app is installed, leave it alone", and a false answer trashes it.
That was already safe, but not for either reason previously offered. "Its
consumers are order-independent" is a non-sequitur — order-independence defends
against reordering, not loss. "A collapse preserves the ASCII skeleton" is
simply false, per the mechanism above. The real protection is that a pure-ASCII
line cannot collapse with anything: any line that could collide with it carries
the shared uncollatable weight, which no ASCII line's key has. Exhaustively, all
2800 byte-distinct strings of length 1–4 over `{a,A,b,0,.,-,_}` survive `sort -u`
under both C and en_US.UTF-8, and the two sets are identical.

That argument has one seam, which is why the pin beats the proof. It needs every
looked-up id to be ASCII, and `looks_like_bundle_id`'s `*[!A-Za-z0-9._-]*` is a
bracket range — so it is `LC_COLLATE`-dependent in exactly the way
[the display-columns note](#display-columns) describes, and it *accepts*
`com.café.app` under en_US.UTF-8 while rejecting it under C. A non-ASCII id can
therefore reach `bid_is_kept`, and two installed apps whose ids differ only by a
combining mark would collapse and orphan a live one. That needs two such apps to
exist, so it was never a real-world loss — but the safety of a deletion should
not rest on a coincidence about which strings Apple ships. The range itself is
left alone deliberately: changing it changes which orphans get offered for
deletion, which deserves its own commit rather than a ride-along.

The general lesson matches the display-columns bug: this failed **quietly**. No
error, no wrong-looking output — just fewer lines than went in, on inputs nobody
tests with. `sort -u` is the only sort in cdm whose output depends on the
comparison being byte-exact; plain `sort` merely reorders, and `awk '!seen[$0]++'`
(used for the same job in `scan_projects`) de-duplicates on bytes and is immune.

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
