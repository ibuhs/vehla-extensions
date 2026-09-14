# Hertzly Radio Dock Widget

Hertzly brings internet radio to Vehla's Dock. Its compact and inline surfaces
provide quick playback controls, while the popup includes the FM-inspired
tuner, country and station browsing, favorites, and Hertzly's support and
legal links.

## Build

Requirements:

- macOS 14 or newer on Apple silicon
- Xcode with the Swift 6 toolchain
- The adjacent Vehla Swift SDK at `../../sdk/swift`

```sh
cd vehla-extensions/extensions/hertzly-dock-widget
./build.sh
```

Install the generated `dist/Hertzly` folder through Vehla. It contains the
manifest and signed bundle in the package layout Vehla expects. Then enable
Hertzly in Settings > Dock Widgets.

## Development checks

```sh
swift test
swift run --package-path ../../sdk/swift vehla-swift validate dist/Hertzly
```

Station data and streams come from Radio Browser. Hertzly stores selected
country, favorites, and country caches only in the package data directory
provided by Vehla. Network refreshes stop when the widget is hidden; active
radio playback continues until paused or the extension is disabled.
