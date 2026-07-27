#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
derived="$root/.xcode-derived"

(
  cd "$root"
  xcodebuild -scheme "ToolboxNative" -configuration Release \
    -destination "platform=macOS" -derivedDataPath "$derived" build
)

framework="$derived/Build/Products/Release/PackageFrameworks/ToolboxWorkspace.framework"
binary="$framework/Versions/A/ToolboxWorkspace"
[[ -x "$binary" ]] || { echo "ToolboxWorkspace binary was not produced." >&2; exit 1; }

bundle="$root/bin/ToolboxWorkspace.bundle"
contents="$bundle/Contents"
rm -rf "$bundle"
mkdir -p "$contents/MacOS" "$contents/Resources"
/usr/bin/install -m 644 "$root/Info.plist" "$contents/Info.plist"
/usr/bin/install -m 755 "$binary" "$contents/MacOS/ToolboxWorkspace"
/usr/bin/codesign --force --deep --sign - --timestamp=none \
  --identifier com.ibuhs.vehla.toolbox.workspace "$bundle"

package="$root/dist/Toolbox"
rm -rf "$package"
mkdir -p "$package/bin"
/usr/bin/install -m 644 "$root/extension.json" "$package/extension.json"
/usr/bin/ditto "$bundle" "$package/bin/ToolboxWorkspace.bundle"
echo "Built and signed $bundle"
echo "Install this folder in Vehla: $package"
