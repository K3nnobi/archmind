#!/usr/bin/env python3
"""Storage units and shared filesystems, using the approved monitor collector."""
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("archmind_monitor", Path(__file__).with_name("live-monitor.py"))
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


def collect(summary=False):
    paths = [("/", "/")] if summary else [("/", "/"), ("Home", str(Path.home()))]
    disks = monitor.storage_info(paths, monitor.mount_entries(monitor.read_text("/proc/self/mountinfo")))
    lines = []
    for disk in disks:
        if summary:
            return f"{monitor.amount(disk['used'])} used / {monitor.amount(disk['total'])}; {monitor.amount(disk['available'])} available"
        shared = " (shared filesystem)" if len(disk["paths"]) > 1 else ""
        lines.extend(["Paths: " + " + ".join(disk["paths"]) + shared,
                      "Filesystem: " + disk["fs"]])
        for label, key in (("Total", "total"), ("Used", "used"), ("Available", "available"), ("Reserved/unavailable", "reserved")):
            value = disk[key]
            lines.append(f"{label:<21} {monitor.amount(value):>12}  ({monitor.amount(value, True)})")
        lines.append("")
    lines.extend(["GB = 1,000,000,000 bytes; GiB = 1,073,741,824 bytes.",
                  "Available is space usable by this user, as reported by the filesystem.",
                  "Shared Btrfs subvolumes are not added together.",
                  "Btrfs metadata allocation and quotas may limit actual writable space."])
    return "\n".join(lines)


if __name__ == "__main__":
    print(collect("--summary" in sys.argv))
