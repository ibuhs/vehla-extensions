#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
PRODUCT=NewsDockWidgets
BUNDLE="$ROOT/bin/NewsDockWidget.bundle"
EXECUTABLE="$BUNDLE/Contents/MacOS/NewsDockWidget"

swift build \
  --package-path "$ROOT" \
  --configuration release \
  --arch arm64 \
  --product "$PRODUCT"

BIN_PATH=$(swift build \
  --package-path "$ROOT" \
  --configuration release \
  --arch arm64 \
  --show-bin-path)

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$BIN_PATH/lib$PRODUCT.dylib" "$EXECUTABLE"
chmod 755 "$EXECUTABLE"

# SwiftPM links the SDK as a dylib; Vehla embeds that product as a framework.
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
    <string>NewsDockWidget</string>
    <key>CFBundleIdentifier</key>
    <string>com.ibuhs.vehla.news-reader.bundle</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>News Reader Dock Widget</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.7</string>
    <key>CFBundleVersion</key>
    <string>7</string>
    <key>NSPrincipalClass</key>
    <string>NewsDockWidgetPlugin</string>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$BUNDLE"
echo "Built $BUNDLE"
