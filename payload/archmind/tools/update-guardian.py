#!/usr/bin/env python3
"""Post-update health scan and pending-task generator for ArchMind."""

from __future__ import annotations

import argparse
import glob
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from maintenance_state import (
    load_package_baseline,
    load_tasks,
    resolve_task,
    save_package_baseline,
    upsert_task,
)
from runtime_files import safe_text


ROOT = Path(os.environ.get("ARCHMIND_TEST_ROOT", "/"))
TOOLS = Path(__file__).resolve().parent
CORE = TOOLS.parent


def rooted(path: str) -> Path:
    return ROOT / path.lstrip("/")


def run(command: list[str], timeout=20) -> subprocess.CompletedProcess | None:
    try:
        return subprocess.run(
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
        return None


def package_installed(name: str) -> bool:
    if not shutil.which("pacman"):
        return False
    result = run(["pacman", "-Q", name])
    return bool(result and result.returncode == 0)


def current_package_versions() -> dict[str, str]:
    if not shutil.which("pacman"):
        return {}
    result = run(["pacman", "-Q"], timeout=40)
    if not result or result.returncode != 0:
        return {}
    packages = {}
    for line in result.stdout.splitlines():
        fields = line.split(None, 1)
        if len(fields) == 2:
            packages[fields[0]] = fields[1]
    return packages


def detect_external_package_changes() -> set[str]:
    current = current_package_versions()
    if not current:
        return set()
    previous = load_package_baseline()
    changed = {
        package for package in set(previous) | set(current)
        if previous and previous.get(package) != current.get(package)
    }
    save_package_baseline(current)
    return changed


def record_changed_packages(packages: set[str]) -> list[str]:
    created = []
    kernel_packages = {
        "linux", "linux-lts", "linux-zen", "linux-hardened",
        "nvidia", "nvidia-lts", "nvidia-open", "nvidia-open-lts", "nvidia-dkms", "nvidia-open-dkms",
    }
    if packages & kernel_packages:
        upsert_task(
            "reboot-required",
            "Restart the computer",
            "A kernel or NVIDIA kernel-module package changed. Finish current work and reboot before diagnosing driver problems.",
            "critical",
            "Update Guardian",
        )
        created.append("reboot-required")
    if packages & {"gnome-shell", "mutter"}:
        upsert_task(
            "gnome-session-restart",
            "Restart the GNOME session",
            "GNOME Shell or Mutter changed. Log out and log back in after the package transaction.",
            "warning",
            "Update Guardian",
        )
        created.append("gnome-session-restart")
        if package_installed("gnome-rounded-blur"):
            upsert_task(
                "rounded-blur-rebuild",
                "Rebuild gnome-rounded-blur",
                "GNOME Shell or Mutter changed. Run: yay -S gnome-rounded-blur --rebuild",
                "warning",
                "Update Guardian",
            )
            created.append("rounded-blur-rebuild")
    if "grub" in packages:
        upsert_task(
            "plymouth-reapply",
            "Audit the Plymouth patch",
            "GRUB changed. Open Package Center → Plymouth / Boot Visual and use status/reapply if required.",
            "warning",
            "Update Guardian",
        )
        created.append("plymouth-reapply")
    if packages & {"nvidia-utils", "nvidia-settings"}:
        config = Path(os.environ.get("ARCHMIND_DATA_HOME", str(Path.home() / "ArchMind"))) / "Config/NVIDIA/vibrance.conf"
        if config.is_file():
            upsert_task(
                "nvibrant-reapply",
                "Check NVIDIA Vibrance",
                "NVIDIA userspace packages changed. Reapply NVIDIA Vibrance after restarting the graphical session.",
                "info",
                "Update Guardian",
            )
            created.append("nvibrant-reapply")
    return created


def newest_boot_artifact() -> float:
    candidates = []
    for pattern in ("/boot/vmlinuz-*", "/boot/initramfs-*.img", "/boot/EFI/Linux/*.efi"):
        candidates.extend(glob.glob(str(rooted(pattern))))
    mtimes = []
    for candidate in candidates:
        try:
            mtimes.append(Path(candidate).stat().st_mtime)
        except OSError:
            pass
    return max(mtimes, default=0.0)


def boot_time() -> float:
    override = os.environ.get("ARCHMIND_TEST_BOOT_TIME")
    if override:
        try:
            return float(override)
        except ValueError:
            return 0.0
    try:
        uptime = float(rooted("/proc/uptime").read_text(encoding="ascii").split()[0])
    except (OSError, ValueError, IndexError):
        return 0.0
    return time.time() - uptime


def scan_reboot() -> str:
    artifact = newest_boot_artifact()
    started = boot_time()
    if artifact and started and artifact > started + 2:
        upsert_task(
            "reboot-required",
            "Restart the computer",
            "A boot image is newer than the current system session.",
            "critical",
            "Update Guardian",
        )
        return "required"
    if artifact and started:
        resolve_task("reboot-required")
        return "not required"
    return "unavailable"


def scan_plymouth() -> str:
    data_home = Path(os.environ.get("ARCHMIND_DATA_HOME", str(Path.home() / "ArchMind")))
    state = data_home / "Config/Patches/Plymouth/state.conf"
    if not state.is_file():
        resolve_task("plymouth-reapply")
        return "not configured"
    helper = CORE / "patches/plymouth/plymouth-patch.sh"
    if not helper.is_file():
        upsert_task("plymouth-reapply", "Repair the Plymouth integration", "The Plymouth patch helper is missing.", "warning", "Update Guardian")
        return "helper missing"
    result = run(["bash", str(helper), "--check"], timeout=40)
    if result and result.returncode == 0:
        resolve_task("plymouth-reapply")
        return "healthy"
    upsert_task(
        "plymouth-reapply",
        "Reapply the Plymouth patch",
        "The saved Plymouth state no longer matches the boot configuration. Review status before reapplying.",
        "warning",
        "Update Guardian",
    )
    return "needs attention"


def scan_rounded_blur() -> str:
    if not package_installed("gnome-rounded-blur"):
        resolve_task("rounded-blur-rebuild")
        return "not installed"
    if not shutil.which("dconf"):
        return "dconf unavailable"
    result = run(["dconf", "read", "/org/gnome/shell/extensions/blur-my-shell/rounded-blur-found"])
    value = result.stdout.strip().lower() if result and result.returncode == 0 else ""
    if value == "true":
        resolve_task("rounded-blur-rebuild")
        return "detected"
    upsert_task(
        "rounded-blur-rebuild",
        "Rebuild gnome-rounded-blur",
        "Blur My Shell does not detect rounded blur. Rebuild the AUR package, then log out and back in.",
        "warning",
        "Update Guardian",
    )
    return "not detected"


def scan_nvibrant() -> str:
    data_home = Path(os.environ.get("ARCHMIND_DATA_HOME", str(Path.home() / "ArchMind")))
    config = data_home / "Config/NVIDIA/vibrance.conf"
    if not config.is_file():
        resolve_task("nvibrant-reapply")
        return "not configured"
    if not shutil.which("nvibrant"):
        upsert_task("nvibrant-reapply", "Repair NVIDIA Vibrance", "nvibrant is configured but its executable is missing.", "warning", "Update Guardian")
        return "executable missing"
    if not shutil.which("systemctl"):
        return "systemctl unavailable"
    result = run(["systemctl", "--user", "is-enabled", "nvibrant.service"])
    if result and result.returncode == 0:
        resolve_task("nvibrant-reapply")
        return "enabled"
    upsert_task("nvibrant-reapply", "Repair NVIDIA Vibrance", "The configured nvibrant user service is not enabled.", "warning", "Update Guardian")
    return "service disabled"


def scan(externally_changed=None) -> int:
    if externally_changed is None:
        externally_changed = detect_external_package_changes()
    if externally_changed:
        record_changed_packages(externally_changed)
    checks = {
        "Restart": scan_reboot(),
        "Plymouth patch": scan_plymouth(),
        "Rounded blur": scan_rounded_blur(),
        "NVIDIA Vibrance": scan_nvibrant(),
    }
    pending = [task for task in load_tasks() if not task["resolved"]]
    print("ArchMind Update Guardian\n")
    print(f"Packages changed since last scan: {len(externally_changed)}")
    for label, value in checks.items():
        print(f"{label:<20} {safe_text(value)}")
    print(f"\nPending tasks: {len(pending)}")
    if pending:
        print("Open Maintenance Center → Pending Tasks for instructions.")
    return 1 if any(task["severity"] == "critical" for task in pending) else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--changed", nargs="*", default=[], metavar="PACKAGE")
    parser.add_argument("--changed-file", metavar="PATH")
    parser.add_argument("--no-scan", action="store_true")
    parser.add_argument("--baseline-only", action="store_true", help="record package changes without running full diagnostics")
    args = parser.parse_args()
    changed = {item.strip() for item in args.changed if item.strip()}
    if args.changed_file:
        try:
            changed.update(line.strip().split()[0] for line in Path(args.changed_file).read_text(encoding="utf-8").splitlines() if line.strip())
        except OSError as error:
            print(f"Could not read changed-package list: {error}", file=sys.stderr)
            return 1
    try:
        if changed:
            created = record_changed_packages(changed)
            print(f"Update Guardian recorded {len(set(created))} follow-up task(s).")
        external = detect_external_package_changes()
        if external:
            record_changed_packages(external)
        if args.baseline_only:
            return 0
        return 0 if args.no_scan else scan(external)
    except (OSError, ValueError) as error:
        print(f"Update Guardian unavailable: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
