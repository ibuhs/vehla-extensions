#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
derived="$root/.xcode-derived"

(
  cd "$root"
  xcodebuild -scheme "MarkdownQuickNative" -configuration Release \
    -destination "platform=macOS" -derivedDataPath "$derived" build
)

framework="$derived/Build/Products/Release/PackageFrameworks/MarkdownQuickWorkspace.framework"
binary="$framework/Versions/A/MarkdownQuickWorkspace"
[[ -x "$binary" ]] || { echo "MarkdownQuickWorkspace binary was not produced." >&2; exit 1; }

bundle="$root/bin/MarkdownQuickWorkspace.bundle"
contents="$bundle/Contents"
rm -rf "$bundle"
mkdir -p "$contents/MacOS" "$contents/Resources"
/usr/bin/install -m 644 "$root/Info.plist" "$contents/Info.plist"
/usr/bin/install -m 755 "$binary" "$contents/MacOS/MarkdownQuickWorkspace"
/usr/bin/codesign --force --deep --sign - --timestamp=none \
  --identifier com.ibuhs.vehla.markdown-quick.workspace "$bundle"

package="$root/dist/MarkdownQuick"
rm -rf "$package"
mkdir -p "$package/bin"
/usr/bin/install -m 644 "$root/extension.json" "$package/extension.json"
/usr/bin/ditto "$bundle" "$package/bin/MarkdownQuickWorkspace.bundle"
echo "Built and signed $bundle"
echo "Install this folder in Vehla: $package"
