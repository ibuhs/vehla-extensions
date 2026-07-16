#!/bin/zsh
set -euo pipefail

root="${0:A:h}"
scratch="$root/../../DerivedData/SwiftStoreSDK/swift-hello"

swift build \
  --package-path "$root" \
  --scratch-path "$scratch/arm64" \
  --triple arm64-apple-macosx14.0 \
  --configuration release

arm64_bin="$(swift build \
  --package-path "$root" \
  --scratch-path "$scratch/arm64" \
  --triple arm64-apple-macosx14.0 \
  --configuration release \
  --show-bin-path)"

mkdir -p "$root/bin"
/usr/bin/install -m 755 \
  "$arm64_bin/SwiftHelloExtension" \
  "$root/bin/swift-hello"
/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --identifier com.vehla.examples.swift-hello \
  "$root/bin/swift-hello"

echo "Built arm64 executable at $root/bin/swift-hello"
