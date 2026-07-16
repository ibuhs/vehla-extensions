#!/bin/zsh
set -euo pipefail

root="${0:A:h}"
scratch="$root/../../DerivedData/SwiftStoreSDK/swift-hello"

swift build \
  --package-path "$root" \
  --scratch-path "$scratch/arm64" \
  --triple arm64-apple-macosx14.0 \
  --configuration release

swift build \
  --package-path "$root" \
  --scratch-path "$scratch/x86_64" \
  --triple x86_64-apple-macosx14.0 \
  --configuration release

arm64_bin="$(swift build \
  --package-path "$root" \
  --scratch-path "$scratch/arm64" \
  --triple arm64-apple-macosx14.0 \
  --configuration release \
  --show-bin-path)"
x86_64_bin="$(swift build \
  --package-path "$root" \
  --scratch-path "$scratch/x86_64" \
  --triple x86_64-apple-macosx14.0 \
  --configuration release \
  --show-bin-path)"

mkdir -p "$root/bin"
/usr/bin/lipo -create \
  "$arm64_bin/SwiftHelloExtension" \
  "$x86_64_bin/SwiftHelloExtension" \
  -output "$root/bin/swift-hello"
chmod 755 "$root/bin/swift-hello"

echo "Built universal executable at $root/bin/swift-hello"
