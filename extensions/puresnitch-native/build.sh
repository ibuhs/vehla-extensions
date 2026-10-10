#!/bin/zsh
set -euo pipefail
task_root="${0:A:h}"
cd "$task_root"
identity="${SIGNING_IDENTITY:--}"
mkdir -p .build/service bin dist

swift build -c release --arch arm64 --disable-sandbox
product_dir="$(swift build -c release --arch arm64 --show-bin-path)"

helper_sources=(Sources/Helper/*.swift)
shared_sources=(Sources/Shared/*.swift)
xcrun --sdk macosx swiftc -swift-version 5 -O -target arm64-apple-macos14.0 \
  "${shared_sources[@]}" "${helper_sources[@]}" -lsqlite3 \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$task_root/Sources/Helper/Info.plist" \
  -o .build/service/PureSnitchHelper
xcrun --sdk macosx swiftc -swift-version 5 -O -target arm64-apple-macos14.0 \
  Sources/Shared/CompanionPolicy.swift Sources/Companion/main.swift \
  -o .build/service/VehlaPureSnitchService

python3 Scripts/package.py "$product_dir/libPureSnitchWorkspace.dylib"
# Vehla embeds this SDK as a framework; SwiftPM's CLI builds it as a dylib.
# Bind the workspace to the host's one SDK image rather than a private copy.
/usr/bin/install_name_tool -change @rpath/libVehlaNativeUISDK.dylib \
  @rpath/VehlaNativeUISDK.framework/Versions/A/VehlaNativeUISDK \
  bin/PureSnitchWorkspace.bundle/Contents/MacOS/PureSnitchWorkspace
app="bin/PureSnitchWorkspace.bundle/Contents/Resources/Vehla PureSnitch Service.app"
if [[ "$identity" == "-" ]]; then
  signing_options=(--timestamp=none)
else
  signing_options=(--timestamp --options runtime)
fi
/usr/bin/codesign --force --sign "$identity" "${signing_options[@]}" \
  --identifier com.kailalabs.vehla.puresnitch.helper "$app/Contents/MacOS/PureSnitchHelper"
/usr/bin/codesign --force --sign "$identity" "${signing_options[@]}" \
  --identifier com.kailalabs.vehla.puresnitch.service "$app"
/usr/bin/codesign --force --sign "$identity" "${signing_options[@]}" \
  --identifier com.kailalabs.vehla.puresnitch.workspace bin/PureSnitchWorkspace.bundle
/usr/bin/codesign --verify --deep --strict bin/PureSnitchWorkspace.bundle
zsh Scripts/test_loading.sh "${1:-}"
python3 Scripts/package.py --dist
print "Install Local Package in Vehla: $task_root/dist/PureSnitch"
print "Helper installation and firewall enforcement remain opt-in."
