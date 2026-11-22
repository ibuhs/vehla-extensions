#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
PRODUCT=AgentApprovals
BUNDLE="$ROOT/bin/$PRODUCT.bundle"
EXECUTABLE="$BUNDLE/Contents/MacOS/$PRODUCT"
PACKAGE="$ROOT/dist/Agent Approvals"

swift build --build-system native --package-path "$ROOT" --configuration release --arch arm64 --product "$PRODUCT"
BIN_PATH=$(swift build --build-system native --package-path "$ROOT" --configuration release --arch arm64 --show-bin-path)

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$BIN_PATH/lib$PRODUCT.dylib" "$EXECUTABLE"
chmod 755 "$EXECUTABLE"
# The Notch SDK is a static library inside the binary, so there is no framework reference to rewrite.

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AgentApprovals</string>
    <key>CFBundleIdentifier</key>
    <string>com.michaelwiseman.vehla.agent-approvals.bundle</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Agent Approvals</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSPrincipalClass</key>
    <string>AgentApprovalsPlugin</string>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$BUNDLE"

rm -rf "$PACKAGE"
mkdir -p "$PACKAGE/bin"
/usr/bin/install -m 644 "$ROOT/extension.json" "$PACKAGE/extension.json"
/usr/bin/ditto "$BUNDLE" "$PACKAGE/bin/$PRODUCT.bundle"

echo "Built and signed $BUNDLE"
echo "Install this folder in Vehla: $PACKAGE"
