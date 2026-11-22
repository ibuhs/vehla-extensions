# SDK Changelog

## Unreleased

### Added

- Published `VehlaNotchSDK` for Store API 4 Notch / Island extensions: live
  activities described as data and tabs backed by a view controller. It is a
  static library; Vehla embeds no framework for it.
- `vehla-swift validate` accepts `runtime: "notch"`.
- Added the Notch Lab sample extension.
- Any extension can post a Notch live activity as data (Store API 4):
  `Store.notchActivity` / `Store.endNotchActivity` in the TypeScript and Swift
  Store SDKs, and `showNotchActivity` / `endNotchActivity` on
  `VehlaWorkspaceContext`. Added the Focus Timer sample.
- A Notch tab may ask for a taller Notch with `height` in its manifest entry.
- Published `VehlaNativeUISDK` for Store API 2 hosted SwiftUI/AppKit workspaces.
- Published `VehlaDockWidgetSDK` for Store API 3 compact, inline, and popup
  Dock widget surfaces.
- Added Native UI and Dock Widget tests.
- Extended `vehla-swift` validation, signing, and packaging support to
  `executable`, `nativeUI`, and `dockWidget` runtimes.
- Documented local AI, theme updates, secrets, clipboard integration, lifecycle,
  in-process security, and dynamic framework host coupling.

### Changed

- TypeScript SDK package metadata now uses the repository's MIT license.
- SDK build artifacts and SwiftPM/Xcode state are ignored.
- CLI validation describes native runtimes as having full app access instead
  of labeling publisher-signed packages unsafe.
