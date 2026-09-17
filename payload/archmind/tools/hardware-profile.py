#!/usr/bin/env python3
"""Read-only hardware and platform capability detection for ArchMind."""

from __future__ import annotations

import argparse
import glob
import json
import os
from pathlib import Path
import shutil
import subprocess

from runtime_files import safe_text


ROOT = Path(os.environ.get("ARCHMIND_TEST_ROOT", "/"))


def rooted(path: str) -> Path:
    return ROOT / path.lstrip("/")


def command_output(command: list[str], timeout=4) -> str:
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
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return safe_text(result.stdout) if result.returncode == 0 else ""


def gpu_vendors() -> list[str]:
    vendors = set()
    for vendor_file in glob.glob(str(rooted("/sys/class/drm/card*/device/vendor"))):
        try:
            vendor = Path(vendor_file).read_text(encoding="ascii").strip().lower()
        except OSError:
            continue
        vendors.add({"0x10de": "NVIDIA", "0x1002": "AMD", "0x8086": "Intel"}.get(vendor, vendor))
    if not vendors and ROOT == Path("/") and shutil.which("lspci"):
        output = command_output(["lspci", "-nn"])
        for line in output.splitlines():
            lower = line.lower()
            if not any(kind in lower for kind in ("vga", "3d controller", "display controller")):
                continue
            if "nvidia" in lower:
                vendors.add("NVIDIA")
            if "amd" in lower or "ati" in lower:
                vendors.add("AMD")
            if "intel" in lower:
                vendors.add("Intel")
    return sorted(vendors)


def boot_loader() -> str:
    if rooted("/boot/grub/grub.cfg").is_file() or rooted("/etc/default/grub").is_file():
        return "GRUB"
    if rooted("/boot/loader/loader.conf").is_file() or rooted("/efi/loader/loader.conf").is_file():
        return "systemd-boot"
    if ROOT == Path("/") and shutil.which("bootctl"):
        output = command_output(["bootctl", "is-installed"])
        if output.strip().lower() == "yes":
            return "systemd-boot"
    return "Unknown"


def initramfs_tool() -> str:
    if rooted("/etc/mkinitcpio.conf").is_file():
        return "mkinitcpio"
    if rooted("/etc/dracut.conf").exists() or rooted("/etc/dracut.conf.d").is_dir():
        return "dracut"
    return "Unknown"


def mkinitcpio_mode() -> str:
    path = rooted("/etc/mkinitcpio.conf")
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return "Unknown"
    hooks = next((line for line in text.splitlines() if line.strip().startswith("HOOKS=")), "")
    return "systemd" if "systemd" in hooks.split("#", 1)[0] else "udev"


def desktop() -> str:
    current = os.environ.get("XDG_CURRENT_DESKTOP", "")
    if current:
        return safe_text(current)[:100]
    return "GNOME (installed)" if rooted("/usr/bin/gnome-shell").exists() else "Unknown"


def session_type() -> str:
    return safe_text(os.environ.get("XDG_SESSION_TYPE", "Unknown"))[:40]


def collect() -> dict:
    gpus = gpu_vendors()
    loader = boot_loader()
    initramfs = initramfs_tool()
    hooks = mkinitcpio_mode() if initramfs == "mkinitcpio" else "Not applicable"
    is_laptop = bool(glob.glob(str(rooted("/sys/class/power_supply/BAT*"))))
    is_efi = rooted("/sys/firmware/efi").is_dir()
    current_desktop = desktop()
    profile = {
        "gpu_vendors": gpus,
        "nvidia": "NVIDIA" in gpus,
        "computer": "Laptop" if is_laptop else "Desktop",
        "firmware": "UEFI" if is_efi else "Legacy/unknown",
        "boot_loader": loader,
        "initramfs": initramfs,
        "mkinitcpio_hooks": hooks,
        "desktop": current_desktop,
        "session": session_type(),
        "gnome": "GNOME" in current_desktop.upper() or rooted("/usr/bin/gnome-shell").exists(),
    }
    profile["capabilities"] = {
        "nvidia_vibrance": profile["nvidia"],
        "gnome_integrations": profile["gnome"],
        "plymouth_patch": loader == "GRUB" and initramfs == "mkinitcpio" and hooks == "udev",
    }
    return profile


def display(profile: dict) -> None:
    print("ArchMind Hardware Profile\n")
    print(f"Computer ............ {profile['computer']}")
    print(f"GPU vendors ......... {', '.join(profile['gpu_vendors']) or 'Not detected'}")
    print(f"Desktop ............. {profile['desktop']}")
    print(f"Session ............. {profile['session']}")
    print(f"Firmware ............ {profile['firmware']}")
    print(f"Boot loader ......... {profile['boot_loader']}")
    print(f"Initramfs ........... {profile['initramfs']}")
    print(f"mkinitcpio hooks .... {profile['mkinitcpio_hooks']}")
    print("\nAvailable integrations:")
    labels = {
        "nvidia_vibrance": "NVIDIA Vibrance",
        "gnome_integrations": "GNOME integrations",
        "plymouth_patch": "Plymouth / Boot Visual patch",
    }
    for key, label in labels.items():
        print(f"  {label:<30} {'Supported' if profile['capabilities'][key] else 'Hidden / unsupported'}")
    if not profile["capabilities"]["plymouth_patch"]:
        print("\nThe boot patch is offered only for GRUB + mkinitcpio + traditional udev hooks.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--capability", choices=("nvidia_vibrance", "gnome_integrations", "plymouth_patch"))
    args = parser.parse_args()
    profile = collect()
    if args.capability:
        print("yes" if profile["capabilities"][args.capability] else "no")
        return 0 if profile["capabilities"][args.capability] else 1
    if args.json:
        print(json.dumps(profile, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        display(profile)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
