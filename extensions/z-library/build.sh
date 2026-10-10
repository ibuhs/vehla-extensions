#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
derived="$root/.xcode-derived"

(
  cd "$root"
  xcodebuild -scheme "ZLibraryNative" -configuration Release \
    -destination "platform=macOS" -derivedDataPath "$derived" build
)

framework="$derived/Build/Products/Release/PackageFrameworks/ZLibraryWorkspace.framework"
binary="$framework/Versions/A/ZLibraryWorkspace"
[[ -x "$binary" ]] || { echo "ZLibraryWorkspace binary was not produced." >&2; exit 1; }

bundle="$root/bin/ZLibraryWorkspace.bundle"
contents="$bundle/Contents"
rm -rf "$bundle"
mkdir -p "$contents/MacOS" "$contents/Resources"
/usr/bin/install -m 644 "$root/Info.plist" "$contents/Info.plist"
/usr/bin/install -m 755 "$binary" "$contents/MacOS/ZLibraryWorkspace"
/usr/bin/codesign --force --deep --sign - --timestamp=none \
  --identifier com.kailalabs.vehla.z-library.workspace "$bundle"

package="$root/dist/ZLibrary"
rm -rf "$package"
mkdir -p "$package/bin"
/usr/bin/install -m 644 "$root/extension.json" "$package/extension.json"
/usr/bin/install -m 644 "$root/README.md" "$package/README.md"
/usr/bin/ditto "$bundle" "$package/bin/ZLibraryWorkspace.bundle"
echo "Built and signed $bundle"
echo "Install this folder in Vehla: $package"
