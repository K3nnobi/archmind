#!/usr/bin/env python3
"""Select lightweight ArchMind operating presets without changing system power policy."""

from __future__ import annotations

import argparse
import json
import sys

from maintenance_state import load_profile, resolve_task, save_profile, upsert_task


PROFILES = {
    "normal": {
        "label": "Normal",
        "interval": 1.0,
        "notes": ["Balanced ArchMind interface behavior.", "Live Monitor refreshes every second."],
    },
    "gaming": {
        "label": "Gaming",
        "interval": 1.0,
        "notes": [
            "Keeps the monitor responsive without changing the CPU governor.",
            "Game optimizations remain controlled by gamemoderun per game.",
        ],
    },
    "quiet": {
        "label": "Quiet",
        "interval": 5.0,
        "notes": ["Reduces ArchMind monitoring frequency.", "Does not change fan curves or hardware power limits."],
    },
    "diagnostic": {
        "label": "Diagnostic",
        "interval": 0.5,
        "notes": ["Uses the fastest supported Live Monitor refresh.", "Intended for temporary troubleshooting."],
    },
}


def current() -> tuple[str, dict]:
    state = load_profile()
    name = state.get("profile", "normal")
    if name not in PROFILES:
        name = "normal"
    return name, PROFILES[name]


def set_profile(name: str) -> None:
    selected = PROFILES[name]
    save_profile(name, selected["interval"], selected["notes"])
    if name == "gaming":
        upsert_task(
            "gaming-profile-reminder",
            "Use GameMode per game",
            "Add gamemoderun %command% to the Steam launch options of games that should use the Gaming profile integrations.",
            "info",
            "Operating Profiles",
        )
    else:
        resolve_task("gaming-profile-reminder")


def display() -> None:
    name, selected = current()
    print("ArchMind Operating Profiles\n")
    print(f"Current profile ...... {selected['label']}")
    print(f"Monitor interval ..... {selected['interval']:g} second(s)")
    print("\nBehavior:")
    for note in selected["notes"]:
        print(f"  - {note}")
    print("\nAvailable profiles:")
    for key, profile in PROFILES.items():
        marker = "*" if key == name else " "
        print(f"  {marker} {profile['label']:<12} Live Monitor {profile['interval']:g}s")


def interactive() -> int:
    display()
    print("\n1) Normal\n2) Gaming\n3) Quiet\n4) Diagnostic\n0) Exit")
    choice = input("\nChoice: ").strip()
    selected = {"1": "normal", "2": "gaming", "3": "quiet", "4": "diagnostic"}.get(choice)
    if not selected:
        print("No profile changes made.")
        return 0
    answer = input(f"Type APPLY to activate the {PROFILES[selected]['label']} profile: ").strip()
    if answer != "APPLY":
        print("Cancelled. No profile changes made.")
        return 0
    set_profile(selected)
    print(f"Profile activated: {PROFILES[selected]['label']}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--set", choices=tuple(PROFILES))
    parser.add_argument("--interval", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--interactive", action="store_true")
    args = parser.parse_args()
    try:
        if args.set:
            set_profile(args.set)
        name, profile = current()
        if args.interval:
            print(f"{profile['interval']:g}")
        elif args.json:
            print(json.dumps({"profile": name, **profile}, ensure_ascii=False, indent=2, sort_keys=True))
        elif args.interactive:
            return interactive()
        else:
            display()
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Operating profile unavailable: {error}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled. No profile changes made.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
