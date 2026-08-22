# Reading Tools

Reading Tools is a QuickGlass-only Native UI extension. Select text, then run
an analysis or open a large-type display from the QuickGlass overflow menu.

| | |
| --- | --- |
| Extension ID | `com.ibuhs.vehla.reading-tools` |
| Workspace ID | `reading-tools` |
| Version | **1.0.2** |
| Runtime | Vehla Native UI (`nativeUI`) |
| Author | ibuhs |
| License | MIT (`LICENSE`) |
| Minimum OS | macOS 14 |

The workspace normally shows an action reference card. Large Type opens the
workspace with the selected text in a centered, scrollable, selectable display.
All processing stays on this Mac.

## QuickGlass actions

| Action | Delivery | What it does |
| --- | --- | --- |
| Reading Stats | Compact result | Reports words, characters, lines, sentences, estimated syllables, and reading time |
| Word/Character Count | Compact result | Reports only word and character counts |
| Estimated Reading Time | Compact result | Reports word count and reading time at 200 WPM |
| Readability Score | Compact result | Calculates Flesch Reading Ease and a plain-language interpretation |
| Grade Level | Compact result | Calculates the Flesch-Kincaid US grade level |
| Sentence Analysis | Compact result | Counts sentences and reports average words per sentence |
| Syllable Count | Compact result | Estimates English syllables with a deterministic heuristic |
| Large Type | Open palette | Shows the selected text prominently in the native workspace |

## Formulas and counting

Reading time uses `words / 200` minutes. Flesch Reading Ease uses
`206.835 - 1.015(words/sentences) - 84.6(syllables/words)`. Flesch-Kincaid
grade level uses `0.39(words/sentences) + 11.8(syllables/words) - 15.59`,
with results below zero displayed as zero.

Word counting is Unicode-aware. Line counting treats CRLF as one separator and
also supports CR, LF, NEL, and Unicode line and paragraph separators, including
blank lines. Syllables are estimates for English: the heuristic counts vowel
groups, handles common silent-e and consonant-le endings, and always returns at
least one syllable per word.

## Main-thread safety

`performQuickGlassAction` returns immediately. Analysis runs on the
`ReadingToolsWorker` actor. Completion is reported on the main actor.

## Build, test, and install

```sh
# From this directory (vehla-extensions/extensions/reading-tools-native)
swift test
zsh build.sh
```

`build.sh` creates and ad-hoc signs `bin/ReadingToolsWorkspace.bundle`, then
assembles the installable package at `dist/ReadingTools`. Refresh the Store
catalog in Vehla and install **Reading Tools**, or choose that folder with
**Install Local Package**.
