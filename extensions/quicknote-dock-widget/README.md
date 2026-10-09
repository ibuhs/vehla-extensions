# QuickNote

An independent native scratchpad inside Vehla, inspired by [Antinote](https://antinote.io/). Antinote does **not** need to be installed. Your notes live in Vehla's private package directory and never write back to Antinote.

Built by [mcwiseman97](https://github.com/mcwiseman97) and [ibuhs](https://github.com/ibuhs).

## Use

Open the Dock widget and type. Notes autosave after a short pause and flush when the widget hides or closes. The first run includes five editable tutorials for writing, checklists, calculations, capture and importing. New notes need no name: the first line becomes their title.

- **⌘N** creates a note. **⌘[ / ⌘]** and two-finger horizontal swipes over the editor navigate older/newer notes; passing the newest creates a blank note. Swipes commit once when fingers lift; short or cancelled gestures and scroll momentum do not switch notes. Vertical gestures scroll the note normally. Leaving an empty scratch note removes it.
- **⌘F** opens the search pane. Search Stack, Slots or Void. Return opens the first match, or creates a note from an unmatched query.
- **⌘⇧1** promotes the current scratch note. **⌘D** confirms moving it to **The Void**. Restore from the Void tab; no automatic permanent deletion.
- **Keep** assigns one of nine permanent slots. Occupied slots are protected. Slots never expire; set optional scratch note expiry from the menu (default: Never).
- **⌘⇧O** (or the window button beside Keep, the menu, or a sidebar row's context menu) opens a note in its own floating window, like Math Reference. Several notes can be open at once; each window stays open while the dock popup is hidden, edits the same library (the dock editor follows along), keeps its own math and list formatting, and closes with **⌘W**, when its note moves to The Void, or when the widget unloads. Slash commands that act on the dock's selection (such as /new) stay as text there; /copy copies that note.
- **⌘S** exports text. The menu also exports Markdown and a complete JSON library backup, copies text, sends a note to Vehla Notes, and opens find/replace (**⌘⇧F**, literal matching with optional case sensitivity).
- The menu adjusts text size and lined paper. Colors follow Vehla's live theme; Dock tile text follows Vehla's contrast preference. Opening or editing a note never copies it or publishes it to Vehla's shared context/Notch; Copy and Send to Vehla Notes are explicit actions.

## Text tools

Type `/` at the start of a line for a command menu under the caret that narrows as you type, with an icon and description for each command (arrow keys move, Return/Tab or a click runs it, Escape dismisses it for that `/`). It is drawn inside the editor rather than as a separate completion window, which the host's nonactivating popup does not reliably show. Supported commands are `/list`, `/math`, `/sum`, `/average`, `/count`, `/code`, `/text`, `/checkbox`, `/bullet`, `/numbered`, `/date`, `/time`, `/new`, `/search`, `/copy`, `/paste`, `/timer`, `/import` and `/export`. Press Return on a completed command to execute it. Timer arguments work as `/timer 5: Tea`. Unknown commands remain literal text.

Start a note with `list`, `math`, `sum`, `average`, `count` or `code`, optionally followed by `: A title`, to apply that mode to the whole note. Elsewhere in a note, a line holding only one of these keywords (what `/math` and the other mode commands insert; `/list` inserts a `[]` checklist item on its line) starts a section that ends at the next blank line; the rest of the note is unchanged. `/text` ends a section. Section headings are styled as labels; a sum, average or count shows its total on its heading line, and an empty section shows a dimmed hint saying what to type. Math lines wrap early to leave room for their answers; other text keeps the full width. Math variables carry across sections. The footer shows the note's position in the stack (e.g. `3 / 12`, or its slot). Sidebar rows show the same page number. Long notes get an outline rail on the right instead of a scrollbar: one tick per paragraph, list or heading, brighter for what is on screen; ticks hang from the right edge; hovering one previews that block, clicking scrolls to it and dragging along the rail scrubs through the note. Its strip is always reserved, so text never reflows when it appears.

Checklists accept `[]`, `[ ]`, `[x]`, `- [ ]` and `- [x]`; typing the closing `]` at the start of a line adds the space, so the item stays a checkbox. Choosing a command from the slash popup runs it. Click the checkbox to toggle. List notes keep their first line as the title. Plain nonempty body lines receive implicit checkboxes; numbered/bulleted rows, headings and `//` comments do not. Type `/x` at the end of an item to check or uncheck it; the trigger disappears. Item text and checkbox positions stay stable during ordinary typing. Markdown bullet and numbered markers also continue on Return; a blank item exits the list. Tab/Shift-Tab indent/outdent. Plain text stays the source of truth. Headings, bold, italic, underline, strikethrough and comments get subtle native styling. **⌘B / ⌘I / ⌘U** wrap selected text. Code notes use a monospaced font and preserve pasted indentation. HTTP(S) links are clickable; **⌘Return** opens the link under the caret through Vehla.

Math supports arithmetic, parentheses, right-associative powers, percentages (`100 + 15% =`, `50% of 200 =`) and variables (`x = pi / 4`, then `sin(x)^2 + cos(x)^2 =`). End an expression with `=`; results appear inline beside each expression without modifying your text. Answers follow the last visual line when an expression wraps, and the last answers stay visible until recalculation completes. Variables carry across math sections in document order; changing an earlier variable recalculates later expressions. Multiplication accepts `2 * sin(x)` and implicit forms such as `5x`, `2sin(x)` and `3(x + 1)`; multiplication and division have equal precedence and evaluate left to right.

Define your own numeric functions in a math section:

```text
math: Function notation
f(x) = 5x - 2
f(1) =
f(2) =
f(3) =
f(4) =
f(5) =
f(6) =
```

Each call shows the substituted rule and output inline (hover an answer to read the complete details), for example `5(4) - 2 = 18`. Repeating calls creates an input/output list like a function table. Functions support multiple parameters (`area(w, h) = w*h`), scientific functions (`wave(x) = sin(x)`) and other user functions (`g(x) = f(x)^2`). Parameters are local to the call; other variables use their current value at the calling line. Definitions and redefinitions apply to later math lines, including later sections, and recalculate when earlier text changes. Names are case-sensitive; built-in scientific functions cannot be redefined. Use 1–16 distinct parameters. Up to 64 function definitions are retained per note analysis; calls are bounded to 16 nested user calls and a shared calculation work limit. Function rules are evaluated numerically when called; invalid rules and recursive cycles report “Check expression” at the call. Definitions remain plain note text, so they persist and export normally.

Choose **More → Math 108X Examples** to create an editable example note for fractions/budgets, function tables, statistics, savings/loans, quadratic features, systems, trendlines, or probability/logic. These examples are opt-in and work in existing libraries. See the [course equation guide](docs/MATH_108X.md) for every helper, argument order, formulas, and textbook sources.

Scientific functions and constants:

- `pi` (or `π`), `tau` and `e`.
- `sin`, `cos`, `tan`; `asin`, `acos`, `atan` (also `arcsin`, `arccos`, `arctan`); `atan2(y, x)`. Angles and inverse-trig answers use **radians**. Use `sin(rad(30)) =` for degrees, or `deg(asin(0.5)) =` to get a degree answer.
- `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`.
- `sqrt`, `cbrt`, `abs`, `ceil`, `floor`, `round` (nearest, ties away from zero), `trunc` (toward zero).
- `ln` (natural logarithm), `log` / `log10` (base 10), `log2`, `log(value, base)`, `exp`, `pow(value, exponent)`, `hypot(x, y)`, and `min` / `max` with one or more arguments.

Calls can nest: `sqrt(pow(3, 2) + pow(4, 2)) =`, `log(81, 3) =`, `exp(ln(5)) =`. Commas separate arguments; use ungrouped numbers inside parentheses, such as `max(1200, 1500)`. Outside parentheses, grouped thousands such as `1,200 + 300 =` remain supported. Scientific notation (`1e-3`) also works. This evaluates numeric expressions, including assigned variables; it does not solve symbolic equations or support complex numbers. Unknown functions/variables, incorrect argument counts, invalid domains and non-finite results show “Check expression”. Calculations use floating-point precision and answers display up to six decimal places.

`//` comments are ignored. Supported unit conversions use `10 km to mi =`: m/cm/mm/km/in/ft/yd/mi, g/kg/lb/oz, ml/l/gal (US), s/min/h, C/F, and m/s/km/h/mph/ft/s. Currency exchange and arbitrary prose math are not implemented. Sum/average extract numbers from non-comment lines. Count reports words, characters and lines.

Type `paste` on a line and press Return (or choose Start AutoPaste from the menu) to start **AutoPaste**. `paste( | )` uses a custom separator. Text copied in any app is appended to that note from the system pasteboard, so it works whether or not Vehla's Clipboard Management is on; copies marked concealed or transient (password managers) are skipped. Capture is opt-in and keeps running after the popup closes, with the Dock tile showing a clipboard icon; it stops on Escape, `paste` again, Stop AutoPaste, changing notes, or closing the widget. Paste/drop an image for local macOS Vision OCR. Image file reading and recognition run off MainActor; images are not stored or uploaded.

Type `timer 5: Tea` or `timer 3:30` on a line and press Return to start a **Vehla timer**. Vehla owns countdowns, notifications and their lifetime, including after the popup closes. `timer pomo` starts a 25-minute focus countdown; break cycles remain under Vehla's timer controls. `timer` starts an in-widget stopwatch; `timer p/r/s` pause/resume, restart and stop it. Older hosts without the app bridge show a clear unavailable message for countdowns and Send to Notes.

## Import Notes

Choose **Import Notes** from the menu or footer. The importer detects stable and Setapp installations separately from stored data, so notes left behind after uninstall can still be imported. It reuses this project's existing Antinote database discovery, modern `notes` parser and legacy Core Data `ZNOTE` parser, including UUID blob identifiers, timestamp decoding and deleted-note filtering.

The preview shows note titles, previews and already-imported identities. Select some or all, then Import. Source databases remain read-only; importing again skips existing identities, preserves local edits and keeps duplicates out even after a note moves to the Void. Dates and permanent slots are preserved. A slot collision puts the imported note in the scratch stack. The former reader's silent 1,000-note limit is removed; explicit limits are 50,000 notes, 2 MB per note and 100 MiB of imported note text.

If no app/database/notes are found, tutorials remain available and the import sheet explains the state. **Choose Files** accepts Antinote SQLite/SQLite3/DB backups, UTF-8 `.txt`/`.md` exports, and this widget's JSON backups. No Antinote launch, Accessibility, Automation permission, shell command or database mutation is used by this flow. Container access may require granting Vehla Full Disk Access and restarting Vehla. Choosing readable exported files or a backup is an alternative.

## Storage and lifecycle

`scratchpad.json` and `scratchpad.previous.json` are stored under `context.dataDirectory`. Atomic writes are serialized by a repository actor and stale revisions cannot overwrite newer ones. Corrupt data surfaces an error rather than silently replacing notes with tutorials. **Recover Previous Save** restores the prior valid library; export a backup before intentionally recovering. JSON import merges instead of overwriting.

The plugin retains one model across compact, inline and popup controllers. AppKit drawing, responder routing, pasteboard reads, native panels and brokered host actions stay on MainActor. Filesystem discovery, SQLite reading, import merging, JSON encode/decode, atomic writes, search, calculations, text-style parsing and OCR run on actors or worker tasks. Visibility work is cancelled on hide; accepted saves drain without blocking lifecycle callbacks. Keyboard monitors are removed on detachment and explicitly yield to other text fields. Undo history resets when the selected note changes.

This is a Dock widget, not Antinote binary compatibility. Vehla owns window placement, activation and shortcuts. Separate application windows, global extension hotkeys, iCloud sync, Antinote's JavaScript marketplace, Vim editing, split-screen editing, live currency rates and PDF export are outside this implementation. All exposed controls perform real operations.

Math answers are read-only selectable text: highlight a result and press ⌘C to copy it. **More → Math Result Color** saves a color choice for the widget and every pop-out editor. Stack/Slots/Void tabs fit within the sidebar, including larger note counts. Lined paper follows native text rows, including wrapping, font changes and scrolling, in both widget and pop-out editors.

## Build and install

macOS 14+, Apple silicon, Swift 6+ with the full Xcode developer tools selected:

```sh
swift test --package-path extensions/quicknote-dock-widget
zsh extensions/quicknote-dock-widget/build.sh
swift run --package-path sdk/swift vehla-swift validate extensions/quicknote-dock-widget/dist/QuickNote
```

On this machine, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` is needed for tests because the selected Command Line Tools installation lacks complete test plugins. The release build uses the native SwiftPM backend, matching the Research widget.

Install `dist/QuickNote` through **Vehla Settings → Store → Install Local Package**, then enable the widget in **Dock Widgets**. Reinstall after rebuilding: Vehla uses its installed copy. Quit and reopen Vehla after updating a previously loaded native bundle; in-process modules remain loaded until the host exits. If both Vehla and Vehla Alpha are running, restart both. A stale loaded descriptor can produce a metadata mismatch even when the installed manifest and binary match. The build produces an arm64, ad-hoc signed bundle linked to Vehla's embedded SDK framework. Store packages are built and signed with the repository's catalog script under the `ibuhs` publisher identity (`com.ibuhs.publisher`), which Vehla trusts by default: `python3 scripts/build-catalog.py --only quicknote-dock-widget` with the `VEHLA_PUBLISHER_*` variables set. Published archives are immutable; increment the manifest version before rebuilding a changed package.

See [architecture and research notes](docs/ARCHITECTURE.md) for inspected sources, SDK contracts and design decisions. Tests cover database compatibility, persistence/recovery, absent Antinote, import idempotency, slot/expiry safety, math/search, native list editing, host bridge use, close-time saves and offscreen rendering. Actual popup routing and file-panel behavior still need checking in an installed Vehla build.


QuickNote uses the package identity `com.wiseman.vehla.quicknote`. On its first run, its storage actor copies the previous widget library from the sibling `com.wiseman.vehla.antinote` data directory, preserving note identities, text, slots, trash, selection, settings and import history. Existing QuickNote data takes precedence; the original files remain intact. A damaged old library reports an error rather than silently replacing notes with tutorials; its valid recovery snapshot is available through Recover Previous Save.

Automatic Apple Notes sync is intentionally absent: supported interfaces do not provide verified preservation of live math, native checklist state and QuickNote commands. See [Apple Notes compatibility research](docs/APPLE_NOTES_COMPATIBILITY.md). Text/Markdown export remains available.


Formatting, checkboxes, summaries and math results are prepared off the main actor. The selected note is prepared before the editor appears on startup; other active notes warm in the background. An in-memory LRU cache retains up to 128 notes and approximately 16 MiB of derived content. Switching back to unchanged notes or reopening the popup restores cached formatting and answers in the same editor update; saving does not invalidate them. Editing a note invalidates only that note's content match. Larger libraries warm a bounded working set and calculate other notes on demand. Derived results are never persisted as user text.

Horizontal two-finger navigation requires at least 120 points of travel, locks direction after 16 points and requires horizontal movement to exceed vertical movement by 2:1. It still commits once at the end of the gesture, ignores momentum and preserves vertical scrolling.
