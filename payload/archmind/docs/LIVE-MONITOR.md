# ArchMind Live Monitor

Integrated into ArchMind 1.5.10 as **System Monitor → Live Monitor**.

```bash
archmind-monitor
```

The monitor is version 0.1.0, with exactly the previously approved code,
layout and one-second default refresh. It is read-only, requires Python 3.10+
with curses, and does not install packages or control processes.

## Keys

- 1 / 2 / 3: dashboard / processes / hardware.
- Space: pause the displayed sample.
- S: CPU or memory sorting.
- U: decimal GB or binary GiB.
- N: next network interface; one interface naturally remains selected.
- C: next group of eight logical cores; page 1/1 naturally remains unchanged.
- Arrows, J/K, Page Up/Down, Home/End: scroll.
- Q, Esc, Ctrl+C: exit. When launched from AFI, press Enter to return to its menu.

Two-column dashboard from 104 terminal columns; vertical panels below that
width. Scroll to see all panels. Minimum usable geometry: 48 by 12.

Options remain available without changing the default:

```bash
archmind-monitor --interval 2
archmind-monitor --interval 0.5
archmind-monitor --no-gpu
archmind-monitor --ascii
archmind-monitor --snapshot --no-gpu
```

Snapshot prints JSON without saving a file. It includes process names and
system details: review before sharing. It is not the Doctor diagnostic report.

## Measurement semantics

- Aggregate CPU: interval utilization of all logical CPUs, 0–100%.
- Process CPU: interval utilization; 100% means one logical CPU, so threaded
  processes can exceed 100%. Very short-lived processes can be missed.
- RAM used: total minus MemAvailable. RSS includes shared pages.
- Swap: logical swap usage; compressed physical zram usage is not separate.
- Storage: root and Home, sharing one entry for the same Btrfs source.
  Available is f_bavail. Btrfs metadata and quotas can limit writable capacity.
- Network: measured byte deltas on one interface, not an ISP speed test.
  N selects another interface; loopback is excluded. RX/TX totals since reset.
- GPU: optional NVIDIA telemetry via nvidia-smi, every three seconds, off the
  UI thread with a timeout. AMD/Intel utilization remains unavailable.
- Temperatures: available kernel sensor files; no sensor labels are guessed.
- Unavailable and first-delta metrics show N/A, not fabricated zero values.
- Container /proc views may describe the host; no cgroup normalization.

GPU polling can wake a discrete GPU. Use --no-gpu when battery consumption
matters. Sensor collection continues in the background while the display is
paused. Collection cost is displayed; faster refresh can cost more CPU.

## Validation

The package includes test-live-monitor.py (metrics, responsive geometry and
PTY lifecycle), test-monitor-handoff.py (AFI/curses handoff) and an exact hash
check against the user-approved prototype.

References: [Linux /proc](https://docs.kernel.org/filesystems/proc.html),
[Python curses](https://docs.python.org/3/library/curses.html),
[btop inspiration](https://github.com/aristocratos/btop).
