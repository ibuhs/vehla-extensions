#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
product_dir="$(swift build -c release --arch arm64 --show-bin-path)"
test_dir="$task_root/.build/loading-test"
framework="$test_dir/VehlaNativeUISDK.framework"
mkdir -p "$framework/Versions/A" "$test_dir/cache"
/usr/bin/install -m 755 "$product_dir/libVehlaNativeUISDK.dylib" "$framework/Versions/A/VehlaNativeUISDK"
/usr/bin/install_name_tool -id @rpath/VehlaNativeUISDK.framework/Versions/A/VehlaNativeUISDK \
  "$framework/Versions/A/VehlaNativeUISDK"
/usr/bin/codesign --force --sign - --timestamp=none "$framework/Versions/A/VehlaNativeUISDK"
ln -sfn Versions/A/VehlaNativeUISDK "$framework/VehlaNativeUISDK"
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path "$test_dir/cache" -I "$product_dir" -F "$test_dir" \
  -framework VehlaNativeUISDK -Xlinker -rpath -Xlinker "$test_dir" \
  Scripts/WorkspaceLoading.swift -o "$test_dir/workspace-loading"
if [[ "${1:-}" == "--render" ]]; then
  "$test_dir/workspace-loading" "$task_root/bin/PureSnitchWorkspace.bundle" "$task_root/.build/preview"
else
  "$test_dir/workspace-loading" "$task_root/bin/PureSnitchWorkspace.bundle"
fi
