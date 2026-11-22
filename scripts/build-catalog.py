#!/usr/bin/env python3

import argparse
import base64
import binascii
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


NEWER_CATALOG_NAME = "catalog-api4.json"
NEWER_CATALOG_API = 4


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


def external_release(
    extension_root: pathlib.Path,
    manifest: dict,
) -> tuple[pathlib.Path, dict] | None:
    stem = f"{extension_root.name}-{manifest['version']}"
    archive = extension_root / "releases" / f"{stem}.zip"
    metadata_path = extension_root / "releases" / f"{stem}.signature.json"
    if not archive.exists() and not metadata_path.exists():
        return None
    if not archive.is_file() or not metadata_path.is_file():
        raise SystemExit(
            f"{extension_root.name} has an incomplete external release."
        )

    metadata = json.loads(metadata_path.read_text())
    publisher = metadata.get("publisher")
    required_publisher_fields = {"id", "name", "keyID", "publicKey"}
    if (
        not isinstance(publisher, dict)
        or not required_publisher_fields.issubset(publisher)
        or not all(
            isinstance(publisher[field], str)
            for field in required_publisher_fields
        )
        or not isinstance(metadata.get("signature"), str)
        or not isinstance(metadata.get("sha256"), str)
    ):
        raise SystemExit(
            f"{metadata_path.name} has incomplete publisher metadata."
        )
    try:
        public_key = base64.b64decode(publisher["publicKey"], validate=True)
        signature = base64.b64decode(metadata["signature"], validate=True)
    except (binascii.Error, ValueError, TypeError):
        raise SystemExit(
            f"{metadata_path.name} has invalid base64 signing metadata."
        )
    if len(public_key) != 32 or len(signature) != 64:
        raise SystemExit(
            f"{metadata_path.name} has invalid Ed25519 signing metadata."
        )

    archive_digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if archive_digest != metadata["sha256"].lower():
        raise SystemExit(
            f"{archive.name} does not match its signed SHA-256 checksum."
        )
    fingerprint = metadata.get("publicKeyFingerprintSHA256")
    if (
        fingerprint is not None
        and (
            not isinstance(fingerprint, str)
            or hashlib.sha256(public_key).hexdigest() != fingerprint.lower()
        )
    ):
        raise SystemExit(
            f"{metadata_path.name} has an invalid public-key fingerprint."
        )
    subprocess.run(
        [
            "swift",
            str(SIGNING_SCRIPT),
            "verify",
            str(archive),
            publisher["publicKey"],
            metadata["signature"],
        ],
        check=True,
    )
    return archive, metadata


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
    # Packages for Store API 4 and up (Notch extensions) are listed in their own file. Released
    # versions of Vehla decode catalog.json as a whole and refuse it when one entry names a runtime
    # or an API they don't know, so a newer package in catalog.json would empty everyone's Store.
    newer_catalog_path = ROOT / NEWER_CATALOG_NAME
    existing_catalog = {"packages": []}
    existing_packages = {}
    if catalog_path.is_file():
        existing_catalog = json.loads(catalog_path.read_text())
    if newer_catalog_path.is_file():
        existing_catalog["packages"] = list(existing_catalog.get("packages", [])) + json.loads(
            newer_catalog_path.read_text()
        ).get("packages", [])
    if existing_catalog.get("packages"):
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
        signed_release = external_release(extension_root, manifest)
        if runtime != "node" and publisher is None and signed_release is None:
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
        elif runtime in {"executable", "nativeUI", "dockWidget", "notch"}:
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

        if signed_release is not None:
            signed_release = external_release(extension_root, manifest)
            if signed_release is None:
                raise SystemExit(
                    f"{extension_root.name} removed its external release while building."
                )

        archive = PACKAGES / f"{extension_root.name}-{version}.zip"
        if signed_release is not None:
            signed_archive, _ = signed_release
            if archive.exists() and archive.read_bytes() != signed_archive.read_bytes():
                raise SystemExit(
                    f"{archive.name} already exists with different signed bytes."
                )
            if not archive.exists():
                shutil.copyfile(signed_archive, archive)
            with tempfile.TemporaryDirectory() as temporary:
                extracted = pathlib.Path(temporary)
                subprocess.run(
                    ["/usr/bin/ditto", "-x", "-k", str(archive), str(extracted)],
                    check=True,
                )
                archived_manifest = (
                    extracted
                    / extension_root.name
                    / "extension.json"
                )
                if (
                    not archived_manifest.is_file()
                    or json.loads(archived_manifest.read_text()) != manifest
                ):
                    raise SystemExit(
                        f"{archive.name} does not contain the catalog manifest "
                        f"under {extension_root.name}."
                    )
        elif archive.exists():
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
        if signed_release is not None:
            _, metadata = signed_release
            catalog_package["publisher"] = metadata["publisher"]
            catalog_package["signature"] = metadata["signature"]
        elif publisher is not None:
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
    newer = [
        package for package in catalog_packages
        if package["manifest"].get("apiVersion", 1) >= NEWER_CATALOG_API
    ]
    classic = [
        package for package in catalog_packages
        if package["manifest"].get("apiVersion", 1) < NEWER_CATALOG_API
    ]
    catalog_path.write_text(
        json.dumps({"schemaVersion": 1, "packages": classic}, indent=2) + "\n"
    )
    if newer or newer_catalog_path.is_file():
        newer_catalog_path.write_text(
            json.dumps({"schemaVersion": 1, "packages": newer}, indent=2) + "\n"
        )
    print(
        f"Built {len(classic)} Store packages in catalog.json"
        f" and {len(newer)} in {NEWER_CATALOG_NAME}."
    )


if __name__ == "__main__":
    main()
