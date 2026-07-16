#!/usr/bin/env python3

import hashlib
import json
import pathlib
import shutil
import subprocess


ROOT = pathlib.Path(__file__).resolve().parent.parent
EXTENSIONS = ROOT / "extensions"
PACKAGES = ROOT / "packages"
ARCHIVE_BASE_URL = (
    "https://raw.githubusercontent.com/ibuhs/vehla-extensions/main/packages"
)


def main() -> None:
    if shutil.which("npm") is None:
        raise SystemExit("npm is required to build Store packages.")
    if not pathlib.Path("/usr/bin/ditto").exists():
        raise SystemExit("/usr/bin/ditto is required to build Store packages.")

    PACKAGES.mkdir(exist_ok=True)
    catalog_packages = []
    package_ids = set()

    extension_roots = sorted(
        path for path in EXTENSIONS.iterdir()
        if path.is_dir() and (path / "extension.json").is_file()
    )
    if not extension_roots:
        raise SystemExit("No extension manifests were found.")

    for extension_root in extension_roots:
        manifest = json.loads((extension_root / "extension.json").read_text())
        package_id = manifest["id"]
        version = manifest["version"]
        if package_id in package_ids:
            raise SystemExit(f"Duplicate package ID: {package_id}")
        package_ids.add(package_id)

        subprocess.run(
            [
                "npm",
                "--prefix",
                str(extension_root),
                "install",
                "--install-links",
            ],
            check=True,
        )

        archive = PACKAGES / f"{extension_root.name}-{version}.zip"
        archive.unlink(missing_ok=True)
        subprocess.run(
            [
                "/usr/bin/ditto",
                "-c",
                "-k",
                "--sequesterRsrc",
                "--keepParent",
                str(extension_root),
                str(archive),
            ],
            check=True,
        )

        catalog_packages.append(
            {
                "manifest": manifest,
                "archiveURL": f"{ARCHIVE_BASE_URL}/{archive.name}",
                "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                "archiveRoot": extension_root.name,
            }
        )

    catalog = {
        "schemaVersion": 1,
        "packages": catalog_packages,
    }
    (ROOT / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n")
    print(f"Built {len(catalog_packages)} Store packages.")


if __name__ == "__main__":
    main()
