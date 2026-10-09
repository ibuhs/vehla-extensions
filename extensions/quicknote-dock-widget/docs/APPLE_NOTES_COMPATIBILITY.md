# Apple Notes compatibility assessment

Research date: 7 October 2026. Decision: do not implement automatic Apple Notes sync under the requirement to preserve all functionality. This is a supported-interface assessment, not a claim that Apple Notes lacks math or checklists.

## Inspected interfaces

Apple's [Math Results documentation](https://support.apple.com/en-ae/guide/notes/apda85974595/mac) describes typed expressions, variables and automatically updated results in upgraded iCloud or On My Mac notes. Apple's [lists documentation](https://support.apple.com/en-ae/guide/notes/apd93c815aa0/mac) describes native checklists, completion state, nesting and optional sorting. These are real Notes features, but do not establish an integration contract for another app's calculation engine or list representation.

The installed application's scripting dictionary at `/System/Applications/Notes.app/Contents/Resources/Notes.sdef` exposes accounts, folders, notes and attachments. Note properties include writable HTML `body`, a name, read-only `plaintext`, ID, container and timestamps. There is no structured Math Results object, expression/result update command, checklist item object or completion-state property. Folder-based text mirroring is feasible through macOS Automation; full-fidelity behavioral sync is not established by this interface. No personal Notes database was opened and no Automation request or write was performed for this research.

Apple's [import/export documentation](https://support.apple.com/en-ae/guide/notes/not201900c07/mac) supports text, rich text, HTML and Markdown import, and Markdown/PDF export. It does not promise that imported formulas become live Math Results or that another editor's state can round-trip. These are manual transfer workflows, not an ongoing change-feed or conflict-resolution API.

The [Notes App Intent schemas](https://developer.apple.com/documentation/appintents/app-schema-domain-notes) describe actions an app implements for system integration. They are not evidence of access to Apple's Notes datastore. Vehla's Dock Widget SDK offers `appActions` and `addToNotes`; this broker has no Apple Notes folder selection, remote note identity, update operation or synchronization contract. It remains the explicit Send to Vehla Notes action.

## Compatibility requirements

| QuickNote behavior | Supported Apple Notes bridge assessment |
| --- | --- |
| Titles, ordinary text, destination folder | Can be represented using Notes' HTML scripting body and folder objects. |
| Bullets and numbered lists | Can be represented as HTML/Markdown; behavioral equivalence still needs round-trip verification. |
| Implicit checklist rows under `list:` and explicit markers | QuickNote derives interactive checkboxes from text. The scripting dictionary supplies no native checked-item model or documented conversion contract. Text markers alone do not preserve native checklist interaction. |
| Live math, variables, percentages, unit conversions | Apple supports its own typed math. No documented scripting control creates or reads live Math Results, or guarantees QuickNote's grammar/evaluation rules. Copying a numeric answer would make a static snapshot. |
| `sum`, `average`, `count`, slash commands | QuickNote editor/analysis semantics, with no matching Notes scripting behavior. |
| Permanent slots, trash/expiry, AutoPaste, OCR and Vehla timers | QuickNote/host lifecycle and tools, without equivalent Notes synchronization fields or operations. |

The inference from these interfaces is that a text mirror would be possible, but would not meet the requested preservation of functionality. Therefore QuickNote does not automatically create an Apple Notes folder, push notes or request Automation permission. Existing text/Markdown/JSON exports remain available. Reconsider sync only when supported interfaces and a verified compatibility matrix can preserve the requested semantics. Direct writes to Notes' private database and Accessibility-driven editing would bypass the SDK architecture and are not a dependable solution.
