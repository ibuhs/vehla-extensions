#!/usr/bin/env python3

import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parent.parent
EXTENSIONS = ROOT / "extensions"
PACKAGES = ROOT / "packages"
ARCHIVE_BASE_URL = (
    "https://raw.githubusercontent.com/ibuhs/vehla-extensions/main/packages"
)


def package_digest(root: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        if path.name in {"README.md", ".DS_Store"}:
            continue
        relative = path.relative_to(root).as_posix()
        digest.update(relative.encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


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
        if archive.exists():
            with tempfile.TemporaryDirectory() as temporary:
                extracted = pathlib.Path(temporary)
                subprocess.run(
                    ["/usr/bin/ditto", "-x", "-k", str(archive), str(extracted)],
                    check=True,
                )
                archived_root = extracted / extension_root.name
                if package_digest(extension_root) != package_digest(archived_root):
                    raise SystemExit(
                        f"{archive.name} already exists with different package contents. "
                        "Increment the manifest version before rebuilding."
                    )
        else:
            with tempfile.TemporaryDirectory() as temporary:
                staged_root = pathlib.Path(temporary) / extension_root.name
                shutil.copytree(
                    extension_root,
                    staged_root,
                    ignore=shutil.ignore_patterns("README.md", ".DS_Store"),
                )
                subprocess.run(
                    [
                        "/usr/bin/ditto",
                        "-c",
                        "-k",
                        "--sequesterRsrc",
                        "--keepParent",
                        str(staged_root),
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
