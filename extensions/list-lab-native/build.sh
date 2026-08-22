#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
derived="$root/.xcode-derived"

(
  cd "$root"
  xcodebuild -scheme "ListLabNative" -configuration Release \
    -destination "platform=macOS" -derivedDataPath "$derived" build
)

framework="$derived/Build/Products/Release/PackageFrameworks/ListLabWorkspace.framework"
binary="$framework/Versions/A/ListLabWorkspace"
[[ -x "$binary" ]] || { echo "ListLabWorkspace binary was not produced." >&2; exit 1; }

bundle="$root/bin/ListLabWorkspace.bundle"
contents="$bundle/Contents"
rm -rf "$bundle"
mkdir -p "$contents/MacOS" "$contents/Resources"
/usr/bin/install -m 644 "$root/Info.plist" "$contents/Info.plist"
/usr/bin/install -m 755 "$binary" "$contents/MacOS/ListLabWorkspace"
/usr/bin/codesign --force --deep --sign - --timestamp=none \
  --identifier com.ibuhs.vehla.list-lab.workspace "$bundle"

package="$root/dist/ListLab"
rm -rf "$package"
mkdir -p "$package/bin"
/usr/bin/install -m 644 "$root/extension.json" "$package/extension.json"
/usr/bin/ditto "$bundle" "$package/bin/ListLabWorkspace.bundle"
echo "Built and signed $bundle"
echo "Install this folder in Vehla: $package"
