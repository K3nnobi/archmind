#!/usr/bin/env python3
"""ArchMind Monitor 0.1.0 — standalone, read-only Linux prototype.

No installation, network requests, configuration writes or process control.
Python 3.10+; standard library only. See README.md for measurement semantics.
"""
from __future__ import annotations

import argparse
from collections import deque
import csv
import io
import json
import locale
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import unicodedata

VERSION = "0.1.0"


def read_text(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except (OSError, ValueError):
        return ""


def clean(value):
    # External names must never move the cursor or insert terminal escapes.
    return "".join(c for c in str(value)
                   if unicodedata.category(c)[0] not in "CM" and c.isprintable())


def cells(char):
    return 2 if unicodedata.east_asian_width(char) in "WF" else 1


def clip(value, width):
    out, used = [], 0
    for char in clean(value):
        size = cells(char)
        if used + size > width:
            break
        out.append(char)
        used += size
    return "".join(out)


def percent(value):
    return "N/A" if value is None else f"{value:.1f}%"


def amount(value, binary=False):
    if value is None:
        return "N/A"
    base = 1024 if binary else 1000
    units = ("B", "KiB", "MiB", "GiB", "TiB", "PiB") if binary else (
        "B", "kB", "MB", "GB", "TB", "PB")
    number = float(value)
    for unit in units:
        if abs(number) < base or unit == units[-1]:
            return f"{number:.2f} {unit}"
        number /= base


def rate(value, binary=False):
    return "N/A" if value is None else amount(value, binary) + "/s"


def cpu_times(text):
    values = {}
    for line in text.splitlines():
        parts = line.split()
        if not parts or not re.fullmatch(r"cpu\d*", parts[0]):
            continue
        try:
            times = tuple(int(n) for n in parts[1:9])
            if len(times) >= 4 and min(times) >= 0:
                values[parts[0]] = times
        except ValueError:
            pass
    return values


def cpu_delta(previous, current):
    result = {}
    for name, ticks in current.items():
        old = previous.get(name)
        value = None
        if old is not None and len(old) == len(ticks):
            diffs = [now - before for now, before in zip(ticks, old)]
            total = sum(diffs)
            # iowait can go backwards; do not invent a sample after resets.
            if total > 0 and min(diffs) >= 0:
                idle = diffs[3] + (diffs[4] if len(diffs) > 4 else 0)
                value = 100.0 * (total - idle) / total
        result[name] = value
    return result


def memory_info(text):
    fields = {}
    for line in text.splitlines():
        try:
            key, value = line.split(":", 1)
            fields[key] = int(value.split()[0]) * 1024
        except (ValueError, IndexError):
            continue
    total, available = fields.get("MemTotal"), fields.get("MemAvailable")
    swap, free = fields.get("SwapTotal"), fields.get("SwapFree")
    return {"total": total, "available": available,
            "used": max(0, total - available) if total is not None and available is not None else None,
            "swap_total": swap,
            "swap_used": max(0, swap - free) if swap is not None and free is not None else None}


def network_counters(text):
    result = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        name, payload = line.rsplit(":", 1)
        values = payload.split()
        try:
            if len(values) >= 16 and name.strip() != "lo":
                result[name.strip()] = (int(values[0]), int(values[8]))
        except ValueError:
            pass
    return result


def network_delta(old, current, elapsed):
    result = {}
    for name, (rx, tx) in current.items():
        before = old.get(name)
        valid = before is not None and elapsed > 0
        result[name] = {"received": rx, "sent": tx,
                        "down": (rx - before[0]) / elapsed if valid and rx >= before[0] else None,
                        "up": (tx - before[1]) / elapsed if valid and tx >= before[1] else None}
    return result


def parse_process(text, page_size):
    # comm is parenthesized and may itself include spaces, ')' and newlines.
    left, right = text.find("("), text.rfind(")")
    if left < 0 or right <= left:
        return None
    try:
        tail = text[right + 1:].split()
        pid = int(text[:left].strip())
        return {"pid": pid, "name": clean(text[left + 1:right]),
                "state": tail[0], "ticks": int(tail[11]) + int(tail[12]),
                "start": int(tail[19]), "rss": max(0, int(tail[21])) * page_size}
    except (ValueError, IndexError):
        return None


def process_delta(previous, current, elapsed, hz, mem_total):
    result = []
    for pid, process in current.items():
        old = previous.get(pid)
        cpu = None
        if old and old["start"] == process["start"] and elapsed > 0:
            ticks = process["ticks"] - old["ticks"]
            if ticks >= 0:
                cpu = 100.0 * ticks / hz / elapsed
        result.append({**process, "cpu": cpu,
                       "memory_percent": 100.0 * process["rss"] / mem_total if mem_total else None})
    return result


def unescape_mount(value):
    return re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), value)


def mount_entries(text):
    entries = []
    for line in text.splitlines():
        try:
            head, tail = line.split(" - ", 1)
            a, b = head.split(), tail.split()
            entries.append({"device": a[2], "mount": unescape_mount(a[4]),
                            "fs": b[0], "source": unescape_mount(b[1])})
        except (ValueError, IndexError):
            pass
    return entries


def storage_info(paths, mounts):
    result, groups = [], {}
    for label, path in paths:
        try:
            real = os.path.realpath(path)
            matching = [m for m in mounts if real == m["mount"] or
                        real.startswith(m["mount"].rstrip("/") + "/")]
            mount = max(matching, key=lambda m: len(m["mount"])) if matching else None
            stat = os.statvfs(real)
            # Btrfs subvolumes can have different anonymous st_dev identifiers.
            if mount and mount["fs"] == "btrfs":
                key = ("btrfs", mount["source"])
            else:
                key = ("device", os.stat(real).st_dev)
            if key in groups:
                groups[key]["paths"].append(label)
                continue
            item = {"paths": [label], "fs": mount["fs"] if mount else "unknown",
                    "total": stat.f_blocks * stat.f_frsize,
                    "used": (stat.f_blocks - stat.f_bfree) * stat.f_frsize,
                    "available": max(0, stat.f_bavail) * stat.f_frsize,
                    "reserved": max(0, stat.f_bfree - stat.f_bavail) * stat.f_frsize}
            groups[key] = item
            result.append(item)
        except OSError:
            result.append({"paths": [label], "fs": "unavailable", "total": None,
                           "used": None, "available": None, "reserved": None})
    return result


class Collector:
    def __init__(self, proc=Path("/proc"), home=None):
        self.proc = Path(proc)
        self.home = str(home or Path.home())
        self.hz = os.sysconf("SC_CLK_TCK")
        self.page_size = os.sysconf("SC_PAGE_SIZE")
        self.old_cpu, self.old_net, self.old_processes = {}, {}, {}
        self.cpu_at = self.net_at = self.process_at = None
        info = read_text(self.proc / "cpuinfo")
        self.model = next((line.split(":", 1)[1].strip() for line in info.splitlines()
                           if line.startswith("model name") and ":" in line), "CPU")

    def sample(self):
        begin = time.monotonic()
        ticks = cpu_times(read_text(self.proc / "stat"))
        cpu_at = time.monotonic()
        cpu = cpu_delta(self.old_cpu, ticks)
        memory = memory_info(read_text(self.proc / "meminfo"))
        counters = network_counters(read_text(self.proc / "net/dev"))
        net_at = time.monotonic()
        networks = network_delta(self.old_net, counters, net_at - self.net_at if self.net_at else 0)
        current = {}
        try:
            with os.scandir(self.proc) as entries:
                for entry in entries:
                    if entry.name.isdecimal():
                        item = parse_process(read_text(Path(entry.path) / "stat"), self.page_size)
                        if item:
                            current[item["pid"]] = item
        except OSError:
            pass
        process_at = time.monotonic()
        processes = process_delta(self.old_processes, current,
                                  process_at - self.process_at if self.process_at else 0,
                                  self.hz, memory["total"])
        self.old_cpu, self.old_net, self.old_processes = ticks, counters, current
        self.cpu_at, self.net_at, self.process_at = cpu_at, net_at, process_at
        default = None
        for line in read_text(self.proc / "net/route").splitlines()[1:]:
            parts = line.split()
            try:
                if len(parts) >= 4 and parts[1] == "00000000" and int(parts[3], 16) & 1:
                    default = parts[0]
                    break
            except ValueError:
                pass
        disks = storage_info([("/", "/"), ("Home", self.home)],
                             mount_entries(read_text(self.proc / "self/mountinfo")))
        try:
            uptime = float(read_text(self.proc / "uptime").split()[0])
        except (ValueError, IndexError):
            uptime = None
        return {"cpu": cpu, "model": self.model, "memory": memory,
                "networks": networks, "default_network": default, "storage": disks,
                "processes": processes, "uptime": uptime,
                "load": clean(read_text(self.proc / "loadavg").split(" / ")[0]).split()[:3],
                "sample_ms": (time.monotonic() - begin) * 1000,
                "sampled_at": time.time(), "scope": "host /proc; not cgroup-limited"}


def number(text):
    try:
        value = float(text.strip())
        return value if math.isfinite(value) else None
    except ValueError:
        return None


def hardware_sample(sysroot=Path("/sys"), gpu_command=None):
    temperatures = []
    for sensor in sorted((sysroot / "class/hwmon").glob("hwmon*/temp*_input")):
        value = number(read_text(sensor))
        if value is not None and -50000 <= value <= 250000:
            name = read_text(sensor.parent / "name").strip() or sensor.parent.name
            label = read_text(sensor.with_name(sensor.name.replace("_input", "_label"))).strip()
            temperatures.append({"name": clean(f"{name} {label or sensor.stem}"), "celsius": value / 1000})
    if not temperatures:
        for sensor in sorted((sysroot / "class/thermal").glob("thermal_zone*/temp")):
            value = number(read_text(sensor))
            if value is not None and -50000 <= value <= 250000:
                temperatures.append({"name": clean(read_text(sensor.parent / "type").strip()),
                                     "celsius": value / 1000})
    gpus, status = [], "NVIDIA telemetry unavailable (optional)"
    if gpu_command:
        try:
            completed = subprocess.run(
                [gpu_command, "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu",
                 "--format=csv,noheader,nounits"], capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=0.8, check=False,
                env={**os.environ, "LC_ALL": "C"})
            if completed.returncode == 0:
                for row in csv.reader(io.StringIO(completed.stdout)):
                    if len(row) != 5:
                        continue
                    used, total = number(row[2]), number(row[3])
                    gpus.append({"name": clean(row[0]), "usage": number(row[1]),
                                 "used": used * 1024**2 if used is not None else None,
                                 "total": total * 1024**2 if total is not None else None,
                                 "temperature": number(row[4])})
                status = "NVIDIA / nvidia-smi" if gpus else status
        except (OSError, subprocess.TimeoutExpired):
            status = "NVIDIA query failed or timed out"
    return {"temperatures": temperatures, "gpus": gpus, "status": status,
            "sampled_at": time.monotonic()}


class HardwareWorker:
    def __init__(self, enabled=True):
        self.command = shutil.which("nvidia-smi") if enabled else None
        self.stop_event = threading.Event()
        self.lock = threading.Lock()
        self.result = {"temperatures": [], "gpus": [], "status": "Reading sensors...", "sampled_at": None}
        self.thread = threading.Thread(target=self.run, daemon=True)

    def run(self):
        while not self.stop_event.is_set():
            try:
                result = hardware_sample(gpu_command=self.command)
            except OSError:
                result = {"temperatures": [], "gpus": [], "status": "Sensors unavailable", "sampled_at": None}
            with self.lock:
                self.result = result
            self.stop_event.wait(3)

    def get(self):
        with self.lock:
            return dict(self.result)

    def close(self):
        self.stop_event.set()
        self.thread.join(timeout=1)


class Canvas:
    """Cell-addressed canvas: clipped dynamic names cannot cross a border."""
    def __init__(self, height, width, ascii_only=False):
        self.height, self.width, self.ascii = height, width, ascii_only
        self.rows = [[(" ", 0) for _ in range(width)] for _ in range(height)]

    def text(self, y, x, value, color=0, limit=None):
        if y < 0 or y >= self.height or x < 0:
            return
        available = min(self.width - x, limit if limit is not None else self.width)
        for char in clip(value, available):
            if self.ascii and ord(char) > 127:
                char = "?"
            size = cells(char)
            if x + size > self.width:
                break
            self.rows[y][x] = (char, color)
            for pos in range(1, size):
                self.rows[y][x + pos] = ("", color)
            x += size

    def box(self, y, x, height, width, title):
        if height < 3 or width < 4:
            return
        tl, tr, bl, br, hz, vt = ("+", "+", "+", "+", "-", "|") if self.ascii else "┌┐└┘─│"
        self.text(y, x, tl + hz * (width - 2) + tr, 1)
        self.text(y + height - 1, x, bl + hz * (width - 2) + br, 1)
        for row in range(y + 1, y + height - 1):
            self.text(row, x, vt, 1)
            self.text(row, x + width - 1, vt, 1)
        self.text(y, x + 2, " " + title + " ", 2, width - 4)


def bar(value, width, ascii_only=False):
    if value is None:
        return "N/A"
    filled = round(max(0, min(100, value)) * width / 100)
    return ("#" if ascii_only else "━") * filled + ("." if ascii_only else "─") * (width - filled)


def history_graph(values, width, ascii_only=False):
    levels = " .:-=+*#%@" if ascii_only else " ▁▂▃▄▅▆▇█"
    recent = list(values)[-width:]
    return " " * max(0, width - len(recent)) + "".join(
        " " if v is None else levels[min(len(levels) - 1, max(1, math.ceil(v / 100 * (len(levels) - 1))))]
        for v in recent)


class UIState:
    def __init__(self, interval=1.0, ascii_only=False):
        self.tab, self.offset, self.core_page = 1, 0, 0
        self.sort, self.interface = "cpu", None
        self.paused, self.binary, self.ascii = False, False, ascii_only
        self.interval = interval
        self.cpu_history = deque(maxlen=240)
        self.net_history = {}

    def accept(self, sample):
        self.cpu_history.append(sample["cpu"].get("cpu"))
        for name, value in sample["networks"].items():
            self.net_history.setdefault(name, deque(maxlen=240)).append(value["down"])
        for name in list(self.net_history):
            if name not in sample["networks"]:
                del self.net_history[name]


def sorted_processes(sample, order):
    key = "cpu" if order == "cpu" else "rss"
    return sorted(sample["processes"], key=lambda p: (-(p[key] if p[key] is not None else -1), p["pid"]))


def draw_panel(canvas, rect, title, lines):
    y, x, h, w = rect
    canvas.box(y, x, h, w, title)
    for row, line in enumerate(lines[:h - 2]):
        value, color = line if isinstance(line, tuple) else (line, 0)
        canvas.text(y + 1 + row, x + 2, value, color, w - 4)


def cpu_lines(sample, state, width):
    usage = sample["cpu"].get("cpu")
    cores = sorted((k for k in sample["cpu"] if k != "cpu"), key=lambda k: int(k[3:]))
    pages = max(1, math.ceil(len(cores) / 8))
    page = state.core_page % pages
    lines = [sample["model"], (f"Total {percent(usage)}  " + bar(usage, max(4, width - 21), state.ascii), 2),
             (history_graph(state.cpu_history, width - 4, state.ascii), 1)]
    for i in range(0, 8, 2):
        chunk = cores[page * 8 + i:page * 8 + i + 2]
        lines.append("    ".join(f"{name:<7} {percent(sample['cpu'][name]):>6}" for name in chunk))
    lines.append(f"C: cores {page + 1}/{pages}   Load: {' '.join(sample['load'])}")
    return lines


def memory_lines(sample, state, hardware):
    mem = sample["memory"]
    used = mem["used"]
    ratio = 100 * used / mem["total"] if used is not None and mem["total"] else None
    fmt = lambda n: amount(n, state.binary)
    lines = [(f"RAM {percent(ratio)}", 2), f"Used  {fmt(used)} / {fmt(mem['total'])}",
             f"Available  {fmt(mem['available'])}",
             "Swap disabled" if mem["swap_total"] == 0 else f"Swap {fmt(mem['swap_used'])} / {fmt(mem['swap_total'])}",
             "RAM used = total - available"]
    if hardware["gpus"]:
        gpu = hardware["gpus"][0]
        temp = "N/A" if gpu["temperature"] is None else f"{gpu['temperature']:.0f} C"
        lines.extend([(f"GPU {percent(gpu['usage'])} / {temp}", 2),
                      f"VRAM {fmt(gpu['used'])} / {fmt(gpu['total'])}"])
    else:
        lines.append("GPU N/A | 3: sensor details")
    return lines


def disk_lines(sample, state):
    lines = []
    for disk in sample["storage"]:
        labels = " + ".join(disk["paths"])
        shared = " (shared)" if len(disk["paths"]) > 1 else ""
        lines.extend([(f"{labels} / {disk['fs']}{shared}", 2),
                      f"Available {amount(disk['available'], state.binary)} / {amount(disk['total'], state.binary)}",
                      f"Used {amount(disk['used'], state.binary)} | Reserved {amount(disk['reserved'], state.binary)}"])
    lines.extend(["Available = usable by this user", "Btrfs: subvolumes are not added"])
    return lines


def network_lines(sample, state, width):
    networks = sample["networks"]
    if state.interface not in networks:
        state.interface = sample["default_network"]
        if state.interface not in networks:
            state.interface = max(networks, key=lambda n: sum((networks[n]["received"], networks[n]["sent"])), default=None)
    if state.interface is None:
        return ["No readable network interface", "Loopback is excluded"]
    item = networks[state.interface]
    values = state.net_history.get(state.interface, [])
    peak = max((v for v in values if v is not None), default=None)
    graph = [v / peak * 100 if v is not None and peak else (0 if v == 0 else None) for v in values]
    return [(f"{clean(state.interface)} | N: next interface", 2),
            f"Download {rate(item['down'], state.binary)}", f"Upload   {rate(item['up'], state.binary)}",
            (history_graph(graph, width - 4, state.ascii), 1),
            f"Download graph peak: {rate(peak, state.binary)}",
            f"RX {amount(item['received'], state.binary)} | TX {amount(item['sent'], state.binary)}",
            "One interface; totals since reset"]


def process_lines(sample, state, width, limit=None):
    name_width = max(8, width - 42)
    lines = [(f"{'PID':>7}  {'NAME':<{name_width}} {'CPU%':>7} {'RAM%':>6} {'RSS':>12}", 2)]
    processes = sorted_processes(sample, state.sort)
    for p in processes[:limit] if limit is not None else processes:
        name = clip(p["name"], name_width)
        padding = " " * (name_width - sum(cells(c) for c in name))
        lines.append(f"{p['pid']:>7}  {name}{padding} {percent(p['cpu']):>7} {percent(p['memory_percent']):>6} {amount(p['rss'], state.binary):>12}")
    if not processes:
        lines.append("No readable processes (permissions or /proc unavailable)")
    return lines


def hardware_lines(hardware, state):
    lines = [(hardware["status"], 2), "Sensors refresh every 3 seconds; no root required", ""]
    for gpu in hardware["gpus"]:
        lines.extend([(gpu["name"], 2), f"GPU use {percent(gpu['usage'])} | Temperature {gpu['temperature'] if gpu['temperature'] is not None else 'N/A'} C",
                      f"VRAM {amount(gpu['used'], state.binary)} / {amount(gpu['total'], state.binary)}", ""])
    lines.append(("TEMPERATURES / kernel sensor labels", 2))
    lines.extend(f"{item['name']}: {item['celsius']:.1f} C" for item in hardware["temperatures"])
    if not hardware["temperatures"]:
        lines.append("N/A: no readable temperature sensors")
    lines.extend(["", "AMD/Intel GPU load is not implemented in this prototype.",
                  "Missing telemetry is N/A, never an invented zero."])
    return lines


def render(sample, hardware, state, rows, cols):
    screen = Canvas(rows, cols, state.ascii)
    if rows < 12 or cols < 48:
        screen.text(0, 0, "ArchMind Monitor", 2)
        screen.text(2, 0, "Resize to at least 48 x 12. Q: quit", 0)
        return screen
    status = "PAUSED" if state.paused else "LIVE"
    screen.text(0, 1, f"ARCHMIND MONITOR / {VERSION} / {status}", 2)
    screen.text(1, 1, f"1 Dashboard | 2 Processes | 3 Hardware    Refresh {state.interval:g}s", 1)
    body_h, w = rows - 5, cols - 2
    if state.tab == 2:
        lines = process_lines(sample, state, w)
        content = Canvas(max(body_h, len(lines) + 3), w, state.ascii)
        draw_panel(content, (0, 0, content.height, w), f"PROCESSES / sort {state.sort.upper()} / 100% CPU = one core", lines)
    elif state.tab == 3:
        lines = hardware_lines(hardware, state)
        content = Canvas(max(body_h, len(lines) + 2), w, state.ascii)
        draw_panel(content, (0, 0, content.height, w), "HARDWARE", lines)
    else:
        disk_content = disk_lines(sample, state)
        if cols >= 104:
            left, right = (w - 1) * 3 // 5, (w - 1) - (w - 1) * 3 // 5
            mid_h = max(9, len(disk_content) + 2)
            process_y = 12 + mid_h
            content = Canvas(max(body_h, process_y + 9), w, state.ascii)
            draw_panel(content, (0, 0, 10, left), "CPU", cpu_lines(sample, state, left))
            draw_panel(content, (0, left + 1, 10, right), "MEMORY", memory_lines(sample, state, hardware))
            draw_panel(content, (11, 0, mid_h, left), "STORAGE", disk_content)
            draw_panel(content, (11, left + 1, mid_h, right), "NETWORK", network_lines(sample, state, right))
        else:
            disk_h = len(disk_content) + 2
            process_y = 31 + disk_h
            content = Canvas(process_y + 9, w, state.ascii)
            draw_panel(content, (0, 0, 10, w), "CPU", cpu_lines(sample, state, w))
            draw_panel(content, (11, 0, 9, w), "MEMORY", memory_lines(sample, state, hardware))
            draw_panel(content, (21, 0, disk_h, w), "STORAGE", disk_content)
            draw_panel(content, (22 + disk_h, 0, 9, w), "NETWORK", network_lines(sample, state, w))
        ph = content.height - process_y
        draw_panel(content, (process_y, 0, ph, w), f"PROCESSES / {state.sort.upper()} / 100% CPU = one core",
                   process_lines(sample, state, w, max(1, ph - 3)))
    state.offset = max(0, min(state.offset, content.height - body_h))
    for row in range(body_h):
        source = row + state.offset
        if source < content.height:
            screen.rows[row + 3][1:cols - 1] = content.rows[source]
    units = "GiB (1024)" if state.binary else "GB (1000)"
    screen.text(rows - 2, 1, f"READ ONLY | {units} | Collect {sample['sample_ms']:.1f}ms | Scroll {state.offset}/{max(0, content.height - body_h)}", 1)
    screen.text(rows - 1, 1, "Q quit  Space pause  S sort  U units  N network  C cores  Up/Down/Pg scroll", 0, cols - 2)
    return screen


def run_ui(stdscr, args):
    import curses
    if curses.has_colors():
        curses.start_color()
        background = curses.COLOR_BLACK
        try:
            curses.use_default_colors()
            background = -1
        except curses.error:
            pass
        curses.init_pair(1, curses.COLOR_CYAN, background)
        curses.init_pair(2, curses.COLOR_CYAN, background)
    try:
        curses.curs_set(0)
    except curses.error:
        pass
    stdscr.keypad(True)
    stdscr.timeout(100)
    if hasattr(curses, "set_escdelay"):
        curses.set_escdelay(25)
    state, collector = UIState(args.interval, args.ascii), Collector()
    worker = HardwareWorker(not args.no_gpu)
    worker.thread.start()
    sample, hardware = collector.sample(), worker.get()
    state.accept(sample)
    deadline, dirty = time.monotonic() + args.interval, True
    try:
        while True:
            now = time.monotonic()
            if not state.paused and now >= deadline:
                sample, hardware = collector.sample(), worker.get()
                state.accept(sample)
                deadline = time.monotonic() + args.interval
                dirty = True
            if dirty:
                rows, cols = stdscr.getmaxyx()
                canvas = render(sample, hardware, state, rows, cols)
                stdscr.erase()
                for y, row in enumerate(canvas.rows):
                    x = 0
                    while x < cols:
                        start, color, chars = x, row[x][1], []
                        while x < cols and row[x][1] == color:
                            chars.append(row[x][0])
                            x += 1
                        attr = (curses.color_pair(color) if curses.has_colors() and color else 0)
                        if color == 2:
                            attr |= curses.A_BOLD
                        try:
                            stdscr.addstr(y, start, "".join(chars), attr)
                        except curses.error:
                            # A resize can race this frame; the next one redraws.
                            pass
                stdscr.noutrefresh()
                curses.doupdate()
                dirty = False
            key = stdscr.getch()
            if key in (ord("q"), ord("Q"), 27):
                break
            if key == -1:
                continue
            dirty = True
            if key in (ord("1"), ord("2"), ord("3")):
                state.tab, state.offset = key - ord("0"), 0
            elif key == ord(" "):
                state.paused = not state.paused
                if not state.paused:
                    # Reset baselines; do not average CPU over the paused gap.
                    collector = Collector()
                    sample, hardware = collector.sample(), worker.get()
                    state.cpu_history.clear()
                    state.net_history.clear()
                    state.accept(sample)
                    deadline = time.monotonic() + args.interval
            elif key in (ord("s"), ord("S")):
                state.sort = "memory" if state.sort == "cpu" else "cpu"
                state.offset = 0
            elif key in (ord("u"), ord("U")):
                state.binary = not state.binary
            elif key in (ord("c"), ord("C")):
                state.core_page += 1
            elif key in (ord("n"), ord("N")) and sample["networks"]:
                names = sorted(sample["networks"])
                index = names.index(state.interface) if state.interface in names else -1
                state.interface = names[(index + 1) % len(names)]
            elif key in (curses.KEY_DOWN, ord("j")):
                state.offset += 1
            elif key in (curses.KEY_UP, ord("k")):
                state.offset -= 1
            elif key == curses.KEY_NPAGE:
                state.offset += max(1, stdscr.getmaxyx()[0] - 6)
            elif key == curses.KEY_PPAGE:
                state.offset -= max(1, stdscr.getmaxyx()[0] - 6)
            elif key == curses.KEY_HOME:
                state.offset = 0
            elif key == curses.KEY_END:
                state.offset = 10**9
    finally:
        worker.close()


def interval_arg(value):
    try:
        result = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("interval must be a number") from error
    if not math.isfinite(result) or not 0.5 <= result <= 10:
        raise argparse.ArgumentTypeError("interval must be between 0.5 and 10 seconds")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interval", type=interval_arg, default=1.0, metavar="SECONDS")
    parser.add_argument("--ascii", action="store_true", help="use plain terminal characters")
    parser.add_argument("--no-gpu", action="store_true", help="do not run the optional nvidia-smi query")
    parser.add_argument("--snapshot", action="store_true", help="print a read-only JSON snapshot; no file is saved")
    parser.add_argument("--version", action="version", version=f"ArchMind Monitor {VERSION}")
    args = parser.parse_args()
    if sys.platform != "linux":
        parser.error("this prototype requires Linux /proc and /sys")
    if args.snapshot:
        collector = Collector()
        collector.sample()
        time.sleep(args.interval)
        sample = collector.sample()
        sample["hardware"] = hardware_sample(gpu_command=shutil.which("nvidia-smi") if not args.no_gpu else None)
        print(json.dumps(sample, indent=2, ensure_ascii=True, allow_nan=False))
        return 0
    if not sys.stdin.isatty() or not sys.stdout.isatty() or os.environ.get("TERM") in (None, "dumb", "unknown"):
        parser.error("open a terminal to use the dashboard (or use --snapshot)")
    try:
        import curses
    except ImportError:
        parser.error("Python curses is unavailable in this Python installation")
    try:
        locale.setlocale(locale.LC_ALL, "")
    except locale.Error:
        pass
    if "UTF" not in locale.getpreferredencoding(False).upper():
        args.ascii = True
    def terminate(signum, frame):
        raise KeyboardInterrupt
    old_handlers = {sig: signal.signal(sig, terminate) for sig in (signal.SIGTERM, signal.SIGHUP)}
    try:
        curses.wrapper(run_ui, args)
    except KeyboardInterrupt:
        return 0
    except curses.error as error:
        print(f"Terminal unavailable: {error}. Try --ascii or --snapshot.", file=sys.stderr)
        return 1
    finally:
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
