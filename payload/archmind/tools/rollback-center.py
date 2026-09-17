#!/usr/bin/env python3
"""Catalog ArchMind safety snapshots and open registered reversible modules."""

from __future__ import annotations

import argparse
from datetime import datetime
import os
from pathlib import Path
import subprocess
import sys

from maintenance_state import human_size


DATA_HOME = Path(os.environ.get("ARCHMIND_DATA_HOME", str(Path.home() / "ArchMind")))
BACKUP_ROOT = DATA_HOME / "Installer-Backups"
CORE = Path(__file__).resolve().parent.parent


def tree_size(path: Path) -> int:
    total = 0
    for root, directories, files in os.walk(path, followlinks=False):
        directories[:] = [name for name in directories if not (Path(root) / name).is_symlink()]
        for name in files:
            candidate = Path(root) / name
            try:
                if candidate.is_file() and not candidate.is_symlink():
                    total += candidate.stat().st_size
            except OSError:
                pass
    return total


def snapshots() -> list[dict]:
    entries = []
    candidates = []
    installer_items = (BACKUP_ROOT.iterdir() if BACKUP_ROOT.is_dir() and not BACKUP_ROOT.is_symlink() else ())
    for item in installer_items:
        if item.is_dir() and not item.is_symlink() and item.name in {
            "Plymouth", "NVIDIA-Vibrance", "Wine", "GNOME-Drag-Hover",
            "Caps-Lock-No-Delay", "firefox-chatgpt-emoji"
        }:
            candidates.extend(child for child in item.iterdir())
        else:
            candidates.append(item)
    emoji_safety = DATA_HOME / "Backups" / "Safety" / "firefox-chatgpt-emoji"
    if emoji_safety.is_dir() and not emoji_safety.is_symlink():
        candidates.extend(item for item in emoji_safety.iterdir() if item.is_dir() and not item.is_symlink())
    for item in candidates:
        try:
            if item.is_symlink() or not (item.is_file() or item.is_dir()):
                continue
            info = item.stat()
        except OSError:
            continue
        if item.name.startswith("archmind-before-"):
            module = "ArchMind installer"
        elif item.name.startswith("gamemode.ini-"):
            module = "GameMode Blur"
        elif item.parent.name == "Plymouth":
            module = "Plymouth"
        elif item.parent.name == "NVIDIA-Vibrance":
            module = "NVIDIA Vibrance"
        elif item.parent.name == "Wine":
            module = "Wine Compatibility Pack"
        elif item.parent.name == "GNOME-Drag-Hover":
            module = "GNOME Drag Hover"
        elif item.parent.name == "Caps-Lock-No-Delay":
            module = "Caps Lock No Delay"
        elif item.parent.name == "firefox-chatgpt-emoji":
            module = "Firefox / ChatGPT Color Emoji Fix"
        else:
            module = "Configuration"
        entries.append(
            {
                "path": item,
                "module": module,
                "date": datetime.fromtimestamp(info.st_mtime).astimezone().strftime("%Y-%m-%d %H:%M:%S"),
                "size": tree_size(item) if item.is_dir() else info.st_size,
            }
        )
    return sorted(entries, key=lambda entry: entry["path"].stat().st_mtime, reverse=True)


def display() -> None:
    entries = snapshots()
    print("ArchMind Rollback Center\n")
    print(f"Snapshot directory ... {BACKUP_ROOT}")
    print(f"Snapshots found ...... {len(entries)}\n")
    if not entries:
        print("No safety snapshots were found.")
    for index, entry in enumerate(entries[:25], 1):
        print(f"{index:>2}. {entry['module']} | {entry['date']} | {human_size(entry['size'])}")
        print(f"    {entry['path'].name}")
    if len(entries) > 25:
        print(f"\nShowing 25 of {len(entries)} snapshots.")
    print("\nRegistered reversible modules:")
    print("  Plymouth / Boot Visual")
    print("  NVIDIA Vibrance")
    print("  GameMode Blur hooks")
    print("  Wine Compatibility Pack backup catalog")
    print("  GNOME Drag Hover")
    print("  Caps Lock No Delay")
    print("  Firefox / ChatGPT Color Emoji Fix")
    print("\nInstaller snapshots are cataloged but are not restored blindly.")


def run_helper(relative: str) -> int:
    helper = CORE / relative
    if not helper.is_file() or helper.is_symlink():
        print(f"Reversible helper unavailable: {helper}", file=sys.stderr)
        return 1
    interpreter = sys.executable if helper.suffix == ".py" else "bash"
    return subprocess.run([interpreter, str(helper), "--menu"], check=False).returncode


def interactive() -> int:
    if os.geteuid() == 0 and os.environ.get("ARCHMIND_TEST_SIMULATE") != "1":
        print("Run Rollback Center as your normal user.", file=sys.stderr)
        return 1
    display()
    print("\n1) Review/revert Plymouth")
    print("2) Review/revert NVIDIA Vibrance")
    print("3) Review/revert GameMode Blur")
    print("4) Review Wine Compatibility Pack and its prefix backups")
    print("5) Review/revert GNOME Drag Hover")
    print("6) Review/revert Caps Lock No Delay")
    print("7) Review/revert Firefox / ChatGPT Color Emoji Fix")
    print("0) Exit")
    choice = input("\nChoice: ").strip()
    helpers = {
        "1": "patches/plymouth/plymouth-patch.sh",
        "2": "tools/configure-nvibrant.sh",
        "3": "tools/configure-gamemode-blur.sh",
        "4": "tools/configure-wine-compatibility.sh",
        "5": "tools/configure-gnome-drag-hover.py",
        "6": "tools/configure-capslock-nodelay.sh",
        "7": "tools/configure-firefox-chatgpt-emoji.py",
    }
    if choice not in helpers:
        print("No configuration was restored.")
        return 0
    return run_helper(helpers[choice])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interactive", action="store_true")
    args = parser.parse_args()
    try:
        return interactive() if args.interactive else (display() or 0)
    except (OSError, ValueError) as error:
        print(f"Rollback Center unavailable: {error}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled. No configuration was restored.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
