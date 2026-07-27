#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
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
SIGNING_SCRIPT = ROOT / "scripts" / "publisher-signing.swift"
BUILD_ARTIFACT_NAMES = {
    ".build",
    ".swiftpm",
    ".xcode-derived",
    "DerivedData",
    "dist",
}


def package_digest(root: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative_path = path.relative_to(root)
        if (
            path.name in {"README.md", ".DS_Store"}
            or any(part in BUILD_ARTIFACT_NAMES for part in relative_path.parts)
        ):
            continue
        relative = relative_path.as_posix()
        digest.update(relative.encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def signing_publisher() -> dict[str, str] | None:
    environment = {
        "id": os.environ.get("VEHLA_PUBLISHER_ID"),
        "name": os.environ.get("VEHLA_PUBLISHER_NAME"),
        "keyID": os.environ.get("VEHLA_PUBLISHER_KEY_ID"),
        "privateKey": os.environ.get("VEHLA_PUBLISHER_PRIVATE_KEY"),
    }
    configured = [value is not None for value in environment.values()]
    if not any(configured):
        return None
    if not all(configured):
        missing = [
            key for key, value in environment.items()
            if value is None
        ]
        raise SystemExit(
            "Incomplete publisher signing configuration: "
            + ", ".join(missing)
        )
    if shutil.which("swift") is None:
        raise SystemExit("Swift is required to sign Store packages.")
    public_key = subprocess.run(
        ["swift", str(SIGNING_SCRIPT), "public-key"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    return {
        "id": environment["id"],
        "name": environment["name"],
        "keyID": environment["keyID"],
        "publicKey": public_key,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build and sign Vehla Store catalog packages."
    )
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        metavar="DIRECTORY",
        help=(
            "Build only this extension directory while preserving other "
            "catalog entries. May be repeated."
        ),
    )
    arguments = parser.parse_args()

    if shutil.which("npm") is None:
        raise SystemExit("npm is required to build Store packages.")
    if not pathlib.Path("/usr/bin/ditto").exists():
        raise SystemExit("/usr/bin/ditto is required to build Store packages.")

    PACKAGES.mkdir(exist_ok=True)
    publisher = signing_publisher()
    catalog_path = ROOT / "catalog.json"
    existing_catalog = {"packages": []}
    existing_packages = {}
    if catalog_path.is_file():
        existing_catalog = json.loads(catalog_path.read_text())
        existing_packages = {
            (
                package["manifest"]["id"],
                package["manifest"]["version"],
                package["sha256"],
            ): package
            for package in existing_catalog.get("packages", [])
        }

    extension_roots = sorted(
        path for path in EXTENSIONS.iterdir()
        if path.is_dir() and (path / "extension.json").is_file()
    )
    if not extension_roots:
        raise SystemExit("No extension manifests were found.")
    if arguments.only:
        selected = set(arguments.only)
        available = {path.name for path in extension_roots}
        missing = selected - available
        if missing:
            raise SystemExit(
                "Unknown extension directories: " + ", ".join(sorted(missing))
            )
        extension_roots = [
            path for path in extension_roots if path.name in selected
        ]

    catalog_packages = (
        list(existing_catalog.get("packages", []))
        if arguments.only
        else []
    )
    package_ids = {
        package["manifest"]["id"] for package in catalog_packages
    }

    for extension_root in extension_roots:
        manifest = json.loads((extension_root / "extension.json").read_text())
        package_id = manifest["id"]
        version = manifest["version"]
        runtime = manifest.get("runtime", "node")
        if runtime != "node" and publisher is None:
            raise SystemExit(
                f"{extension_root.name} is native and requires publisher signing."
            )
        if package_id in package_ids:
            if arguments.only:
                catalog_packages = [
                    package
                    for package in catalog_packages
                    if package["manifest"]["id"] != package_id
                ]
                package_ids.remove(package_id)
            else:
                raise SystemExit(f"Duplicate package ID: {package_id}")
        package_ids.add(package_id)

        if (extension_root / "package.json").is_file():
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
        elif runtime in {"executable", "nativeUI", "dockWidget"}:
            build_script = extension_root / "build.sh"
            if not build_script.is_file():
                raise SystemExit(
                    f"{extension_root.name} requires build.sh for its native runtime."
                )
            subprocess.run(["/bin/zsh", str(build_script)], check=True)
            entrypoint = extension_root / manifest["entrypoint"]
            if not entrypoint.exists():
                raise SystemExit(
                    f"{extension_root.name} did not build its native entrypoint."
                )
            if (
                runtime == "executable"
                and (not entrypoint.is_file() or not os.access(entrypoint, os.X_OK))
            ):
                raise SystemExit(
                    f"{extension_root.name} did not build an executable entrypoint."
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
                    ignore=shutil.ignore_patterns(
                        "README.md",
                        ".DS_Store",
                        *BUILD_ARTIFACT_NAMES,
                    ),
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

        catalog_package = {
            "manifest": manifest,
            "archiveURL": f"{ARCHIVE_BASE_URL}/{archive.name}",
            "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "archiveRoot": extension_root.name,
        }
        if publisher is not None:
            existing = existing_packages.get(
                (package_id, version, catalog_package["sha256"])
            )
            if (
                existing is not None
                and existing.get("publisher") == publisher
                and existing.get("signature")
            ):
                signature = existing["signature"]
            else:
                signature = subprocess.run(
                    ["swift", str(SIGNING_SCRIPT), "sign", str(archive)],
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout.strip()
            catalog_package["publisher"] = publisher
            catalog_package["signature"] = signature
        catalog_packages.append(catalog_package)

    catalog_packages.sort(key=lambda package: package["archiveRoot"])
    catalog = {
        "schemaVersion": 1,
        "packages": catalog_packages,
    }
    catalog_path.write_text(json.dumps(catalog, indent=2) + "\n")
    print(f"Built {len(catalog_packages)} Store packages.")


if __name__ == "__main__":
    main()
