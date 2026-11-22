# Mini Terminal (Notch)

A real shell in the Notch. Open the tab and just type: no command palette needed.

- **Real terminal.** Your login shell (zsh, bash, ...) on a pseudo-terminal with its own VT100/xterm emulator:
  cursor addressing, scrollback (3000 lines), the alternate screen (`less`, `vim`, `htop`), 256-colour and truecolor,
  wide characters and emoji, bracketed paste. Ctrl-C, Ctrl-Z, arrows, Option/Cmd word and line movement all work.
- **Black and white by default**, to match the other tabs: every colour a program emits becomes a shade of grey, so
  output stays readable without colour. *Color*, *Hacker Green* (matrix green with a soft CRT glow), *Phosphor* and *Amber* themes are in the **...** menu.
- **Only while a command runs.** The closed Notch shows nothing for the terminal at other times. While a command is
  running (after its first second) it shows a `>` and a blinking cursor, and nothing else; click it to open the
  terminal. It stays out of the way while the terminal tab is open, and can be switched off in **...**.
- **History, searchable.** Every command is recorded with its result, folder, duration and time; repeats are
  merged with a run count. Search by any words in any order, put a command on the prompt or run it, pin favourites,
  remove entries. Commands that look like secrets (`password=`, tokens, API keys, `Authorization:`) and lines that
  start with a space are never stored. History lives only on this Mac.
- **Minimal prompt.** The prompt is just `%` and the cursor (no user, host or folder), switched live from the **...**
  menu; your own prompt comes back when you turn it off, even with themes like powerlevel10k or starship. The real
  folder is shown in the bar above, with a folder icon, and shortened in the middle when long.
- **Room to type.** A slim bar, tight rows, and an optional auto-hide that gives the terminal the full height until
  you move to the top edge.
- **Quick commands (bolt):** your own one-tap commands (edit `terminal.json`), plus pinned and most-used history.
- **Favorite folders (star):** star the folder you are in, then pick it from the star menu to `cd` there
  (or open it in a new session). While a command is running, it opens in a new session instead. Up to 12;
  rename them in `terminal.json`. The `cd` is typed with a leading space, so it stays out of history.
- **Sessions:** up to three shells; a new one opens in the current folder.
- **Small things:** select with the mouse (double-click a word, triple-click a line), Cmd-C / Cmd-V, Cmd-K to clear,
  Cmd-click a link to open it, **drag a file in to paste its path** (quoted), scroll the trackpad for scrollback,
  copy the last command's output with one button (just its output, no escape codes), and a result chip after each
  command (check or x with the time).

## How it knows what is going on
On start it launches your shell with a few lines of extra config (your own startup files still run first, untouched)
that print invisible marks: the command text, start, finish with its exit status, and the folder. zsh reports all of
it; bash reports exit status and folder and the Notch watches the terminal's foreground job; other shells run
plain.

## Safe by design
- It is a shell: it can do anything you can. Nothing is sent anywhere by this extension.
- Pasted text can't end a bracketed paste early or inject escape codes; dropped paths are shell-quoted.
- The terminal never answers queries that would echo text back (only cursor position and device attributes).
- Integration files are written `0600` in a `0700` folder in the extension's data directory.

## Develop
`swift test` runs the emulator, key-encoder, history and PTY tests, including a real zsh on a real pseudo-terminal.
`./build.sh` builds `dist/Mini Terminal`. A few lines of C (`Sources/CPty`) call `forkpty` so the shell gets a
controlling terminal: without it keyboard signals like Ctrl-C would not reach commands.
