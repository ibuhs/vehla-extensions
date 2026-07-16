#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
scratch="$root/../../DerivedData/SwiftStoreSDK/swift-sdk-lab/arm64"

swift build \
  --package-path "$root" \
  --scratch-path "$scratch" \
  --triple arm64-apple-macosx14.0 \
  --configuration release

bin_path="$(swift build \
  --package-path "$root" \
  --scratch-path "$scratch" \
  --triple arm64-apple-macosx14.0 \
  --configuration release \
  --show-bin-path)"

mkdir -p "$root/bin"
/usr/bin/install -m 755 \
  "$bin_path/SwiftSDKLabExtension" \
  "$root/bin/swift-sdk-lab"
/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --identifier com.vehla.examples.swift-sdk-lab \
  "$root/bin/swift-sdk-lab"

echo "Built arm64 executable at $root/bin/swift-sdk-lab"
