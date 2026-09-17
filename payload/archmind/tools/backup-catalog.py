#!/usr/bin/env python3
"""Inspect ArchMind backup metadata and compare its package catalog safely."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile

from maintenance_state import human_size
from runtime_files import safe_text


MAX_METADATA = 4 * 1024 * 1024


def backup_directory() -> Path:
    return Path(os.environ.get("ARCHMIND_BACKUP_DIR", str(Path.home() / "ArchMind/Backups"))).expanduser()


def backups() -> list[Path]:
    directory = backup_directory()
    if not directory.is_dir() or directory.is_symlink():
        return []
    result = [path for path in directory.glob("*.archmind") if path.is_file() and not path.is_symlink()]
    return sorted(result, key=lambda path: path.stat().st_mtime, reverse=True)


def safe_member_name(name: str) -> str:
    normalized = name[2:] if name.startswith("./") else name
    path = PurePosixPath(normalized)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Unsafe archive path: {name}")
    return str(path)


def read_member(archive: tarfile.TarFile, suffixes: tuple[str, ...]) -> tuple[str, bytes] | None:
    matches = []
    for member in archive.getmembers():
        name = safe_member_name(member.name)
        if not member.isfile() or member.issym() or member.islnk():
            continue
        if any(name == suffix or name.endswith("/" + suffix) for suffix in suffixes):
            matches.append((name, member))
    if not matches:
        return None
    matches.sort(key=lambda item: (item[0].count("/"), item[0]))
    name, member = matches[0]
    if member.size > MAX_METADATA:
        raise ValueError(f"Backup metadata is too large: {name}")
    stream = archive.extractfile(member)
    if stream is None:
        raise ValueError(f"Could not read backup member: {name}")
    return name, stream.read(MAX_METADATA + 1)


def decode_lines(data: bytes) -> list[str]:
    text = safe_text(data.decode("utf-8", errors="replace"))
    return [line.strip() for line in text.splitlines() if line.strip()]


def current_packages() -> set[str] | None:
    if not shutil.which("pacman"):
        return None
    try:
        result = subprocess.run(["pacman", "-Qq"], capture_output=True, text=True, timeout=30, check=False, env={**os.environ, "LC_ALL": "C"})
    except (OSError, subprocess.TimeoutExpired):
        return None
    return set(result.stdout.split()) if result.returncode == 0 else None


def inspect(path: Path) -> dict:
    result = {
        "path": path,
        "size": path.stat().st_size,
        "mode": "Unknown",
        "version": "Unknown",
        "created": "Unknown",
        "hostname": "Unknown",
        "user": "Unknown",
        "components": set(),
        "packages": [],
        "checksum_catalog": False,
    }
    try:
        with tarfile.open(path, "r:*") as archive:
            names = [safe_member_name(member.name) for member in archive.getmembers()]
            for name in names:
                parts = PurePosixPath(name).parts
                if parts and parts[0] in {"configs", "gnome", "packages", "project"}:
                    result["components"].add(parts[0])
            manifest = read_member(archive, ("manifest.json", "manifest.txt"))
            if manifest:
                name, data = manifest
                if name.endswith(".json"):
                    metadata = json.loads(data.decode("utf-8", errors="strict"))
                    if isinstance(metadata, dict):
                        for field in ("mode", "version", "created", "hostname", "user"):
                            if field in metadata:
                                result[field] = safe_text(str(metadata[field]))[:200]
                else:
                    for line in decode_lines(data):
                        if ":" in line:
                            key, value = line.split(":", 1)
                            key = key.strip().lower()
                            if key in result:
                                result[key] = safe_text(value.strip())[:200]
            package_member = read_member(archive, ("packages/pacman-all.txt", "packages/pacman-explicit.txt"))
            if package_member:
                packages = []
                for line in decode_lines(package_member[1]):
                    name = line.split()[0]
                    if name.replace("-", "").replace("_", "").replace("+", "").replace(".", "").isalnum():
                        packages.append(name)
                result["packages"] = sorted(set(packages))
            result["checksum_catalog"] = any(name.endswith("checksums.sha256") for name in names)
    except (tarfile.TarError, OSError, UnicodeError, json.JSONDecodeError) as error:
        result["error"] = safe_text(str(error))[:500]
    return result


def display_details(result: dict) -> int:
    print("ArchMind Backup Catalog\n")
    print(f"File ............... {result['path'].name}")
    print(f"Size ............... {human_size(result['size'])}")
    if "error" in result:
        print(f"Status ............. Unreadable: {result['error']}")
        return 1
    print(f"Created ............ {result['created']}")
    print(f"Source host ........ {result['hostname']}")
    print(f"Source user ........ {result['user']}")
    print(f"Backup format ...... {result['version']}")
    print(f"Backup mode ........ {result['mode']}")
    print(f"Components ......... {', '.join(sorted(result['components'])) or 'Not cataloged'}")
    print(f"Checksum catalog ... {'Present' if result['checksum_catalog'] else 'Missing'}")
    print(f"Packages recorded .. {len(result['packages'])}")
    installed = current_packages()
    if installed is None or not result["packages"]:
        print("Package comparison . Unavailable")
    else:
        missing = sorted(set(result["packages"]) - installed)
        extra = sorted(installed - set(result["packages"]))
        print(f"Missing locally .... {len(missing)}")
        print(f"Additional locally . {len(extra)}")
        if missing:
            print("\nFirst packages needed by this backup:")
            for package in missing[:20]:
                print(f"  {package}")
    print("\nThis catalog is read-only. Use Validate Backup before restoration.")
    return 0


def display_list(items: list[Path]) -> None:
    print("ArchMind Backup Catalog\n")
    if not items:
        print(f"No .archmind backups found in {backup_directory()}")
        return
    for index, path in enumerate(items[:30], 1):
        print(f"{index:>2}. {path.name} ({human_size(path.stat().st_size)})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--latest", action="store_true")
    parser.add_argument("--file", type=Path)
    parser.add_argument("--interactive", action="store_true")
    args = parser.parse_args()
    try:
        items = backups()
        if args.file:
            candidate = args.file.expanduser().resolve()
            directory = backup_directory().resolve()
            if candidate.parent != directory or candidate not in [item.resolve() for item in items]:
                raise ValueError("Only regular .archmind files from the configured backup directory are accepted")
            return display_details(inspect(candidate))
        if args.latest:
            if not items:
                display_list(items)
                return 1
            return display_details(inspect(items[0]))
        display_list(items)
        if not args.interactive or not items:
            return 0
        choice = input("\nBackup number to inspect (Enter cancels): ").strip()
        if not choice:
            return 0
        if not choice.isdigit() or not 1 <= int(choice) <= min(30, len(items)):
            print("Invalid backup selection.", file=sys.stderr)
            return 1
        print()
        return display_details(inspect(items[int(choice) - 1]))
    except (OSError, ValueError) as error:
        print(f"Backup catalog unavailable: {error}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled. No backup was modified.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
