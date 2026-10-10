#!/usr/bin/env python3
"""Assemble only generated products; include upstream licensing in every delivery."""
import json
import plistlib
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "extension.json").read_text())
version = manifest["version"]
bundle = root / "bin/PureSnitchWorkspace.bundle"

def plist(path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(values, sort_keys=False))

if sys.argv[1] == "--dist":
    destination = root / "dist/PureSnitch"
    if destination.exists():
        shutil.rmtree(destination)
    (destination / "bin").mkdir(parents=True)
    shutil.copytree(bundle, destination / "bin/PureSnitchWorkspace.bundle")
    for name in ["extension.json", "LICENSE", "README.md", "UPSTREAM.md"]:
        shutil.copy2(root / name, destination / name)
    shutil.make_archive(str(root / "dist" / f"puresnitch-native-{version}"), "zip", destination)
    print(f"Created {destination}")
else:
    if bundle.exists():
        shutil.rmtree(bundle)
    (bundle / "Contents/MacOS").mkdir(parents=True)
    resources = bundle / "Contents/Resources"
    resources.mkdir()
    shutil.copy2(sys.argv[1], bundle / "Contents/MacOS/PureSnitchWorkspace")
    plist(bundle / "Contents/Info.plist", {
        "CFBundleIdentifier": "com.kailalabs.vehla.puresnitch.workspace",
        "CFBundleExecutable": "PureSnitchWorkspace", "CFBundleName": "PureSnitchWorkspace",
        "CFBundlePackageType": "BNDL", "CFBundleShortVersionString": version, "CFBundleVersion": "1",
        "NSPrincipalClass": "PureSnitchWorkspacePlugin",
        "NSHumanReadableCopyright": "MIT License · Copyright © 2026 Moamen Basel. Vehla integration © 2026 Kaila Labs.",
    })
    app = resources / "Vehla PureSnitch Service.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    for name in ["PureSnitchHelper", "VehlaPureSnitchService"]:
        shutil.copy2(root / ".build/service" / name, app / "Contents/MacOS" / name)
    plist(app / "Contents/Info.plist", {
        "CFBundleIdentifier": "com.kailalabs.vehla.puresnitch.service",
        "CFBundleExecutable": "VehlaPureSnitchService", "CFBundleName": "Vehla PureSnitch Service",
        "CFBundleDisplayName": "Vehla PureSnitch Service", "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version, "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "14.0", "LSUIElement": True,
        "NSHumanReadableCopyright": "MIT License · Copyright © 2026 Moamen Basel. Vehla integration © 2026 Kaila Labs.",
    })
    daemon = app / "Contents/Library/LaunchDaemons/com.kailalabs.vehla.puresnitch.helper.plist"
    daemon.parent.mkdir(parents=True)
    shutil.copy2(root / "Sources/Helper/Launchd.plist", daemon)
    for folder in [resources, app / "Contents/Resources"]:
        folder.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / "LICENSE", folder / "LICENSE")
