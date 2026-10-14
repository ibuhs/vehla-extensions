#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
PRODUCT=LofiDockWidget
BUNDLE="$ROOT/bin/LofiDockWidget.bundle"
EXECUTABLE="$BUNDLE/Contents/MacOS/LofiDockWidget"
PACKAGE="$ROOT/dist/LofiDockWidget"

# Optional overrides for restricted CI environments.
SWIFT_OPTIONS=(--scratch-path "${VEHLA_SWIFT_SCRATCH_PATH:-$ROOT/.build}")
if [[ "${VEHLA_SWIFT_DISABLE_SANDBOX:-0}" == 1 ]]; then
  SWIFT_OPTIONS+=(--disable-sandbox -debug-info-format none)
fi

swift build "${SWIFT_OPTIONS[@]}" \
  --package-path "$ROOT" \
  --configuration release \
  --arch arm64 \
  --product "$PRODUCT"

BIN_PATH=$(swift build "${SWIFT_OPTIONS[@]}" \
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
    <string>LofiDockWidget</string>
    <key>CFBundleIdentifier</key>
    <string>com.ibuhs.vehla.lofi.bundle</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Lofi</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.1</string>
    <key>CFBundleVersion</key>
    <string>5</string>
    <key>NSPrincipalClass</key>
    <string>LofiDockWidgetPlugin</string>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$BUNDLE"

rm -rf "$PACKAGE"
mkdir -p "$PACKAGE/bin"
/usr/bin/install -m 644 "$ROOT/extension.json" "$PACKAGE/extension.json"
/usr/bin/install -m 644 "$ROOT/README.md" "$PACKAGE/README.md"
/usr/bin/ditto "$BUNDLE" "$PACKAGE/bin/LofiDockWidget.bundle"

echo "Built and signed $BUNDLE"
echo "Install this folder in Vehla: $PACKAGE"
