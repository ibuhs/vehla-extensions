#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
derived="$root/.xcode-derived"

(
  cd "$root"
  xcodebuild -scheme "LinkLensNative" -configuration Release \
    -destination "platform=macOS" -derivedDataPath "$derived" build
)

framework="$derived/Build/Products/Release/PackageFrameworks/LinkLensWorkspace.framework"
binary="$framework/Versions/A/LinkLensWorkspace"
[[ -x "$binary" ]] || { echo "LinkLensWorkspace binary was not produced." >&2; exit 1; }

bundle="$root/bin/LinkLensWorkspace.bundle"
contents="$bundle/Contents"
rm -rf "$bundle"
mkdir -p "$contents/MacOS" "$contents/Resources"
/usr/bin/install -m 644 "$root/Info.plist" "$contents/Info.plist"
/usr/bin/install -m 755 "$binary" "$contents/MacOS/LinkLensWorkspace"
/usr/bin/codesign --force --deep --sign - --timestamp=none \
  --identifier com.ibuhs.vehla.link-lens.workspace "$bundle"

package="$root/dist/LinkLens"
rm -rf "$package"
mkdir -p "$package/bin"
/usr/bin/install -m 644 "$root/extension.json" "$package/extension.json"
/usr/bin/ditto "$bundle" "$package/bin/LinkLensWorkspace.bundle"
echo "Built and signed $bundle"
echo "Install this folder in Vehla: $package"
