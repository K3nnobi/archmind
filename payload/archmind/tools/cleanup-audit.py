#!/usr/bin/env python3
"""Scan reclaimable Arch Linux data and clean only an explicitly selected category."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

from maintenance_state import human_size
from runtime_files import safe_text


def directory_size(path: Path) -> int:
    total = 0
    if not path.is_dir() or path.is_symlink():
        return 0
    for root, directories, files in os.walk(path, followlinks=False):
        directories[:] = [name for name in directories if not (Path(root) / name).is_symlink()]
        for name in files:
            candidate = Path(root) / name
            try:
                info = candidate.lstat()
            except OSError:
                continue
            if stat.S_ISREG(info.st_mode):
                total += info.st_size
    return total


def command_output(command: list[str], timeout=20) -> tuple[int, str]:
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
            env={**os.environ, "LC_ALL": "C"},
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return 127, safe_text(str(error))
    return result.returncode, safe_text((result.stdout + "\n" + result.stderr).strip())


def orphan_packages() -> list[str]:
    if not shutil.which("pacman"):
        return []
    code, output = command_output(["pacman", "-Qtdq"])
    if code not in (0, 1):
        return []
    return [line.strip() for line in output.splitlines() if line.strip() and line.strip().replace("-", "").replace("_", "").replace("+", "").replace(".", "").isalnum()]


def journal_size() -> str:
    if not shutil.which("journalctl"):
        return "Unavailable"
    code, output = command_output(["journalctl", "--disk-usage"])
    if code:
        return "Unavailable"
    return output.splitlines()[-1] if output else "Unavailable"


def scan() -> dict:
    cache = Path(os.environ.get("ARCHMIND_PACMAN_CACHE", "/var/cache/pacman/pkg"))
    thumbnails = Path.home() / ".cache/thumbnails"
    orphans = orphan_packages()
    return {
        "pacman_cache_path": cache,
        "pacman_cache_size": directory_size(cache),
        "thumbnail_path": thumbnails,
        "thumbnail_size": directory_size(thumbnails),
        "journal_size": journal_size(),
        "orphans": orphans,
    }


def display(result: dict) -> None:
    print("ArchMind Safe Cleanup Audit\n")
    print(f"Pacman cache ......... {human_size(result['pacman_cache_size'])}")
    print(f"Thumbnail cache ...... {human_size(result['thumbnail_size'])}")
    print(f"System journal ....... {result['journal_size']}")
    print(f"Orphan packages ...... {len(result['orphans'])}")
    if result["orphans"]:
        print("\nOrphans (informational; never removed automatically):")
        for package in result["orphans"][:30]:
            print(f"  {package}")
        if len(result["orphans"]) > 30:
            print(f"  ... and {len(result['orphans']) - 30} more")
    print("\nCache totals are upper bounds, not guaranteed reclaimed space.")


def run_mutation(command: list[str]) -> int:
    if os.environ.get("ARCHMIND_TEST_SIMULATE") == "1":
        print("SIMULATED: " + " ".join(command))
        return 0
    try:
        return subprocess.run(command, check=False).returncode
    except OSError as error:
        print(f"Could not start cleanup command: {error}", file=sys.stderr)
        return 1


def clean_thumbnails(path: Path) -> tuple[int, int]:
    expected = Path.home() / ".cache/thumbnails"
    if path != expected:
        raise ValueError("Unexpected thumbnail-cache path")
    for candidate in (Path.home(), Path.home() / ".cache", expected):
        if not candidate.exists():
            return 0, 0
        info = candidate.lstat()
        if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError(f"Unsafe thumbnail-cache directory refused: {candidate}")
    if not path.is_dir() or path.is_symlink():
        return 0, 0
    removed = 0
    failed = 0
    for root, directories, files in os.walk(path, topdown=False, followlinks=False):
        directories[:] = [name for name in directories if not (Path(root) / name).is_symlink()]
        for name in files:
            candidate = Path(root) / name
            try:
                info = candidate.lstat()
                if stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid():
                    candidate.unlink()
                    removed += 1
            except OSError:
                failed += 1
        for name in directories:
            candidate = Path(root) / name
            try:
                candidate.rmdir()
            except OSError:
                pass
    return removed, failed


def interactive() -> int:
    result = scan()
    display(result)
    print("\n1) Trim Pacman cache (keep two installed versions; remove uninstalled cache)")
    print("2) Vacuum system journal older than 14 days")
    print("3) Rebuild thumbnail cache")
    print("4) Show the reviewed orphan-removal command")
    print("0) Exit")
    choice = input("\nChoice: ").strip()
    if choice == "0" or choice not in {"1", "2", "3", "4"}:
        print("No files or packages were removed.")
        return 0
    if choice == "4":
        if not result["orphans"]:
            print("No orphan packages were found.")
        else:
            print("Review every package before running this command manually:")
            print("sudo pacman -Rns -- " + " ".join(result["orphans"]))
        return 0
    answer = input("Type CLEAN to execute only the selected category: ").strip()
    if answer != "CLEAN":
        print("Cancelled. No files were removed.")
        return 0
    if choice == "1":
        if not shutil.which("paccache"):
            print("paccache is unavailable (package: pacman-contrib).", file=sys.stderr)
            return 1
        first = run_mutation(["sudo", "paccache", "-rk2"])
        second = run_mutation(["sudo", "paccache", "-ruk0"]) if first == 0 else first
        return second
    if choice == "2":
        if not shutil.which("journalctl"):
            print("journalctl is unavailable.", file=sys.stderr)
            return 1
        return run_mutation(["sudo", "journalctl", "--vacuum-time=14d"])
    removed, failed = clean_thumbnails(result["thumbnail_path"])
    print(f"Thumbnail files removed: {removed}; failures: {failed}. Nautilus will recreate them.")
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interactive", action="store_true")
    args = parser.parse_args()
    try:
        if args.interactive:
            if os.geteuid() == 0 and os.environ.get("ARCHMIND_TEST_SIMULATE") != "1":
                print("Run as your normal user; sudo is requested only for the selected system category.", file=sys.stderr)
                return 1
            return interactive()
        display(scan())
        return 0
    except ValueError as error:
        print(f"Cleanup refused: {error}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled. No additional cleanup was started.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
