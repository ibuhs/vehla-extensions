#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
PRODUCT=QuickNoteDockWidget
BUNDLE="$ROOT/bin/QuickNoteDockWidget.bundle"
EXECUTABLE="$BUNDLE/Contents/MacOS/QuickNoteDockWidget"
PACKAGE="$ROOT/dist/QuickNote"

swift build --build-system native \
  --package-path "$ROOT" \
  --configuration release \
  --arch arm64 \
  --product "$PRODUCT"

BIN_PATH=$(swift build --build-system native \
  --package-path "$ROOT" \
  --configuration release \
  --arch arm64 \
  --show-bin-path)

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$BIN_PATH/lib$PRODUCT.dylib" "$EXECUTABLE"
chmod 755 "$EXECUTABLE"

install_name_tool \
  -change @rpath/libVehlaDockWidgetSDK.dylib \
  @rpath/VehlaDockWidgetSDK.framework/Versions/A/VehlaDockWidgetSDK \
  "$EXECUTABLE"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>QuickNoteDockWidget</string>
    <key>CFBundleIdentifier</key>
    <string>com.wiseman.vehla.quicknote.bundle</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>QuickNote</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.1.9</string>
    <key>CFBundleVersion</key>
    <string>30</string>
    <key>NSPrincipalClass</key>
    <string>QuickNoteDockWidgetPlugin</string>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$BUNDLE"

rm -rf "$PACKAGE"
mkdir -p "$PACKAGE/bin"
/usr/bin/install -m 644 "$ROOT/extension.json" "$PACKAGE/extension.json"
/usr/bin/ditto "$BUNDLE" "$PACKAGE/bin/QuickNoteDockWidget.bundle"

echo "Built and signed $BUNDLE"
echo "Install this folder in Vehla: $PACKAGE"
