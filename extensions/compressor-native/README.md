# Compressor for Vehla

Compress images, videos, PDFs and other files from inside [Vehla](https://github.com/ibuhs/vehla-extensions), without visible quality loss. Drop files into a Liquid Glass window, pick a destination folder, and Compressor saves the compressed version next to a copy of the original.

**Author:** Ahmad Jerow

## Features

- **Drag and drop, or pick files.** Images, videos, PDFs, documents and folders, in batches.
- **Change your mind any time.** The ⓧ on each row removes it before, during or after compressing. During a batch it stops just that item; files already saved are kept.
- **Fast batches.** Images, PDFs and zips are compressed up to four at a time (about 3x faster on a batch of photos), while videos run one at a time alongside them.
- **Folders your way.** For each folder, choose **Zip folder** (one lossless archive) or **Compress each file**, which compresses every file inside and recreates the folder's structure in the destination.
- **Original kept.** Every compressed file is saved in your destination folder beside an untouched copy of the original. Name clashes become `name (1).ext`, so nothing is overwritten.
- **Never bigger.** A result is kept only if it is meaningfully smaller. Otherwise you get the original and a note saying it is already well optimised.
- **Quality presets.** Smaller, Balanced (the default, visually lossless) and Best quality.
- **Animated progress.** Each item and the whole batch get a glowing progress bar with a slider-style thumb, with the total space saved shown when done.
- **Fast video (optional).** Uses the Mac's hardware encoder: about 6x faster, with files roughly 8-28% larger at the same visual quality. Falls back to the standard encoder automatically if needed.
- **Move originals to Trash (optional, off by default).** After a file is compressed, its copy in the destination is checked byte for byte before the original is moved to the Trash. Originals are never touched when the destination is their own folder.
- **Free-space check** before a batch starts, so a big job doesn't fail halfway.
- **Keeps your Mac awake** while a batch is running.
- **Missing-tool check.** If a required Homebrew tool isn't installed, the window says what's missing and gives you the install command.
- **Plain or tinted Liquid Glass,** switchable from the palette button in the header.

| Type | Method | Quality |
|---|---|---|
| JPEG, HEIC, WebP | macOS `sips` / `cwebp` | High-quality re-encode, set by the preset |
| PNG | `oxipng` if installed, otherwise `ffmpeg` | Lossless |
| Video | `ffmpeg`, H.265 | CRF 28 / 24 / 20 by preset, or Apple's hardware encoder with Fast video |
| PDF | Ghostscript | `/ebook`, `/printer` or `/prepress` by preset |
| Other files and folders | `zip -9` | Lossless |

iPhone videos with spatial audio (Apple's APAC codec) keep that audio unchanged, in a `.mov`.

## Requirements

- A Mac with Apple Silicon, and [Vehla](https://github.com/ibuhs/vehla-extensions).
- macOS 26 or later for the Liquid Glass look. Earlier versions fall back to tinted frosted material.
- These tools, installed with [Homebrew](https://brew.sh):

  ```sh
  brew install ffmpeg ghostscript webp
  brew install oxipng   # optional: smaller PNGs
  ```

- To build it yourself: Xcode with Swift 6 or later.

## Download

Get the latest package from [Releases](https://github.com/aj-salafee/vehla-compressor/releases/latest): no Xcode needed. The release notes explain how to install it, including one Terminal command to clear macOS's download flag (the package isn't notarised by Apple).

## Build and install

To build it yourself instead:

```sh
cd compressor-native
./build.sh
```

Then, in Vehla, open **Settings → Store → Install Local Package** and choose `compressor-native/dist/CompressorGlass`. Open **Compressor** from the palette (`compressor`, `squeeze` or `shrink`).

Compressor is a Vehla *native workspace*. It runs inside Vehla's own process with full app access, so Vehla shows a risk warning and asks for your consent the first time you open it and after every update. Vehla runs its own copy of the package, so reinstall it after any change.

## Tests

```sh
cd compressor-native
swift test
```

The tests use real files and the real tools. Two are opt-in: a large-file test (`LARGE_FILE` and `LARGE_OUT`) and a screenshot test (`SNAPSHOT_DIR`).

## What's in this repo

| Folder | What it is |
|---|---|
| `compressor-native/` | The Compressor: a SwiftUI Liquid Glass workspace for Vehla |
| `sdk/` | Copies of Vehla's SDKs. `compressor-native` builds against the Swift one (`sdk/swift`) |

## Tested

Verified on real files, including a 4.5 GB video (about 12.5 minutes) and a 500-page, 1.4 GB PDF. Larger single images and very large batches have not been tested.

## Licence and credits

Compressor is released under the [MIT licence](LICENSE). Copyright (c) 2026 Ahmad Jerow.

The SDKs in `sdk/` come from [ibuhs/vehla-extensions](https://github.com/ibuhs/vehla-extensions) and are used under its MIT licence (see `sdk/swift/LICENSE`).
