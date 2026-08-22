#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
derived="$root/.xcode-derived"

(
  cd "$root"
  xcodebuild -scheme "NumberCrunchNative" -configuration Release \
    -destination "platform=macOS" -derivedDataPath "$derived" build
)

framework="$derived/Build/Products/Release/PackageFrameworks/NumberCrunchWorkspace.framework"
binary="$framework/Versions/A/NumberCrunchWorkspace"
[[ -x "$binary" ]] || { echo "NumberCrunchWorkspace binary was not produced." >&2; exit 1; }

bundle="$root/bin/NumberCrunchWorkspace.bundle"
contents="$bundle/Contents"
rm -rf "$bundle"
mkdir -p "$contents/MacOS" "$contents/Resources"
/usr/bin/install -m 644 "$root/Info.plist" "$contents/Info.plist"
/usr/bin/install -m 755 "$binary" "$contents/MacOS/NumberCrunchWorkspace"
/usr/bin/codesign --force --deep --sign - --timestamp=none \
  --identifier com.ibuhs.vehla.number-crunch.workspace "$bundle"

package="$root/dist/NumberCrunch"
rm -rf "$package"
mkdir -p "$package/bin"
/usr/bin/install -m 644 "$root/extension.json" "$package/extension.json"
/usr/bin/ditto "$bundle" "$package/bin/NumberCrunchWorkspace.bundle"
echo "Built and signed $bundle"
echo "Install this folder in Vehla: $package"
