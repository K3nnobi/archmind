#!/usr/bin/env python3
"""Deterministic metrics, geometry and real PTY lifecycle tests."""
import argparse
import copy
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "payload/archmind/tools/live-monitor.py"
spec = importlib.util.spec_from_file_location("monitor", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def process_stat(pid=42, name="test ) name", ticks=100, start=300):
    fields = ["S"] + ["0"] * 21
    fields[11], fields[12], fields[19], fields[21] = str(ticks), "10", str(start), "20"
    return f"{pid} ({name}) " + " ".join(fields)


def fixture():
    return {
        "cpu": {"cpu": 25.0, **{f"cpu{i}": float(i % 100) for i in range(32)}},
        "model": "TEST CPU / simulated data", "memory": {"total": 32 * 1024**3,
        "used": 8 * 1024**3, "available": 24 * 1024**3, "swap_total": 0, "swap_used": 0},
        "networks": {"eth0": {"down": 1500000, "up": 200000, "received": 4000000000, "sent": 2000000}},
        "default_network": "eth0", "storage": [{"paths": ["/", "Home"], "fs": "btrfs",
        "total": 119000000000, "used": 109700000000, "available": 9300000000, "reserved": 0}],
        "processes": [{"pid": i, "name": "test-process-" + str(i), "cpu": float(i),
        "rss": 120000000, "memory_percent": 1.2, "state": "S", "start": 20, "ticks": 99} for i in range(24)],
        "uptime": 3600, "load": ["0.4", "0.2", "0.1"], "sample_ms": 2.0}


def hardware():
    return {"gpus": [], "temperatures": [], "status": "Unavailable (test fixture)", "sampled_at": None}


class Metrics(unittest.TestCase):
    def test_cpu_excludes_guest_double_count(self):
        a = m.cpu_times("cpu 100 0 50 800 20 5 5 20 900 200")
        b = m.cpu_times("cpu 120 0 60 870 20 5 5 20 1200 300")
        self.assertAlmostEqual(m.cpu_delta(a, b)["cpu"], 30)

    def test_cpu_initial_hotplug_reset_and_empty(self):
        self.assertIsNone(m.cpu_delta({}, {"cpu": (1, 2, 3, 4)})["cpu"])
        self.assertIsNone(m.cpu_delta({"cpu": (1, 2, 3, 4)}, {"cpu": (0, 2, 3, 4)})["cpu"])
        self.assertIsNone(m.cpu_delta({"cpu": (1, 2, 3, 4)}, {"cpu": (1, 2, 3, 4)})["cpu"])
        self.assertEqual(m.cpu_times("garbage\ncpu bad bad bad"), {})

    def test_memory_and_swap(self):
        result = m.memory_info("MemTotal: 1000 kB\nMemAvailable: 400 kB\nSwapTotal: 500 kB\nSwapFree: 200 kB")
        self.assertEqual(result["used"], 600 * 1024)
        self.assertEqual(result["swap_used"], 300 * 1024)
        self.assertIsNone(m.memory_info("MemTotal: 1000 kB")["used"])

    def test_network_rates_not_link_speed(self):
        result = m.network_delta({"eth0": (1000, 200)}, {"eth0": (3000, 1200)}, 2)["eth0"]
        self.assertEqual(result["down"], 1000)
        self.assertEqual(result["up"], 500)

    def test_network_first_sample_reset_and_loopback(self):
        self.assertIsNone(m.network_delta({}, {"eth0": (0, 0)}, 1)["eth0"]["down"])
        self.assertIsNone(m.network_delta({"eth0": (5, 5)}, {"eth0": (1, 1)}, 1)["eth0"]["down"])
        self.assertEqual(m.network_counters("lo: " + "0 " * 16), {})

    def test_process_parentheses_control_and_fields(self):
        p = m.parse_process(process_stat(name="a ) b\n\x1b[1G"), 4096)
        self.assertEqual(p["pid"], 42)
        self.assertEqual(p["ticks"], 110)
        self.assertEqual(p["rss"], 81920)
        self.assertNotIn("\n", p["name"])
        self.assertNotIn("\x1b", p["name"])
        self.assertIsNone(m.parse_process("invalid", 4096))

    def test_process_interval_cpu_can_exceed_100(self):
        old = {42: m.parse_process(process_stat(ticks=100), 4096)}
        new = {42: m.parse_process(process_stat(ticks=500), 4096)}
        self.assertEqual(m.process_delta(old, new, 2, 100, 1024**3)[0]["cpu"], 200)

    def test_pid_reuse_and_new_process_are_na(self):
        old = {42: m.parse_process(process_stat(start=300), 4096)}
        new = {42: m.parse_process(process_stat(start=500), 4096)}
        self.assertIsNone(m.process_delta(old, new, 1, 100, None)[0]["cpu"])
        self.assertIsNone(m.process_delta({}, new, 1, 100, None)[0]["memory_percent"])

    def test_units_explain_nautilus_difference(self):
        self.assertEqual(m.amount(9300000000), "9.30 GB")
        self.assertEqual(m.amount(9300000000, True), "8.66 GiB")
        self.assertEqual(m.amount(None), "N/A")

    def test_btrfs_subvolume_dedup_and_reserved_blocks(self):
        mounts = m.mount_entries("1 0 0:1 /@ / rw - btrfs /dev/sda2 rw\n2 0 0:2 /@home /home rw - btrfs /dev/sda2 rw")
        stat = os.statvfs_result((4096, 4096, 1000, 400, 300, 0, 0, 0, 0, 255))
        with patch.object(m.os, "statvfs", return_value=stat):
            result = m.storage_info([("/", "/"), ("Home", "/home/test")], mounts)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["paths"], ["/", "Home"])
        self.assertEqual(result[0]["used"], 600 * 4096)
        self.assertEqual(result[0]["available"], 300 * 4096)
        self.assertEqual(result[0]["reserved"], 100 * 4096)

    def test_separate_btrfs_filesystems_not_merged(self):
        mounts = m.mount_entries("1 0 0:1 /@ / rw - btrfs /dev/a rw\n2 0 0:2 /@ /home rw - btrfs /dev/b rw")
        with patch.object(m.os, "statvfs", return_value=os.statvfs("/")):
            result = m.storage_info([("/", "/"), ("Home", "/home")], mounts)
        self.assertEqual(len(result), 2)

    def test_storage_unavailable_and_mount_escapes(self):
        self.assertEqual(m.unescape_mount(r"/some\040path"), "/some path")
        with patch.object(m.os, "statvfs", side_effect=PermissionError):
            self.assertIsNone(m.storage_info([("test", "/")], [])[0]["available"])

    def test_missing_proc_does_not_invent_values(self):
        with tempfile.TemporaryDirectory() as temp:
            snapshot = m.Collector(Path(temp)).sample()
        self.assertEqual(snapshot["cpu"], {})
        self.assertEqual(snapshot["processes"], [])
        self.assertIsNone(snapshot["memory"]["used"])

    def test_optional_gpu_mib_and_na(self):
        output = subprocess.CompletedProcess([], 0, "Test GPU, 50, 1024, 8192, [N/A]\n", "")
        with tempfile.TemporaryDirectory() as temp, patch.object(m.subprocess, "run", return_value=output) as run:
            data = m.hardware_sample(Path(temp), "/mock/nvidia-smi")
        self.assertEqual(data["gpus"][0]["used"], 1024**3)
        self.assertIsNone(data["gpus"][0]["temperature"])
        self.assertFalse(run.call_args.kwargs.get("shell", False))
        self.assertLessEqual(run.call_args.kwargs["timeout"], 1)

    def test_gpu_timeout_nonfatal(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(m.subprocess, "run", side_effect=subprocess.TimeoutExpired("test", 0.8)):
            data = m.hardware_sample(Path(temp), "/mock/nvidia-smi")
        self.assertEqual(data["gpus"], [])
        self.assertIn("timed out", data["status"])

    def test_sensor_label_and_conversion(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            hw = root / "class/hwmon/hwmon0"
            hw.mkdir(parents=True)
            (hw / "name").write_text("coretemp")
            (hw / "temp1_input").write_text("45500")
            (hw / "temp1_label").write_text("Package id 0")
            data = m.hardware_sample(root)
        self.assertEqual(data["temperatures"][0]["celsius"], 45.5)
        self.assertIn("Package id 0", data["temperatures"][0]["name"])

    def test_interval_rejects_invalid_values(self):
        for value in ("nan", "inf", "0", "-2", "100", "oops"):
            with self.assertRaises(argparse.ArgumentTypeError):
                m.interval_arg(value)


class Geometry(unittest.TestCase):
    def test_exact_cell_width_all_layouts_and_tabs(self):
        snapshot = fixture()
        snapshot["model"] = "超長 CPU " * 60 + "\x1b[10G\n"
        snapshot["processes"][0]["name"] = "程序 " * 40
        for rows, cols in ((6, 20), (12, 48), (24, 80), (34, 104), (40, 140), (55, 200)):
            for tab in (1, 2, 3):
                for ascii_only in (False, True):
                    state = m.UIState(ascii_only=ascii_only)
                    state.tab = tab
                    state.accept(snapshot)
                    for offset in (0, 99999):
                        state.offset = offset
                        canvas = m.render(snapshot, hardware(), state, rows, cols)
                        self.assertEqual(len(canvas.rows), rows)
                        for row in canvas.rows:
                            self.assertEqual(len(row), cols)
                            text = "".join(c for c, _ in row)
                            self.assertEqual(sum(m.cells(c) for c in text), cols)
                            self.assertNotIn("\x1b", text)
                            self.assertNotIn("\n", text)

    def test_borders_not_overwritten_by_long_model(self):
        sample = fixture()
        sample["model"] = "X" * 200
        state = m.UIState()
        canvas = m.render(sample, hardware(), state, 40, 140)
        self.assertEqual(canvas.rows[3][1][0], "┌")
        left = (138 - 1) * 3 // 5
        self.assertEqual(canvas.rows[4][left][0], "│")
        self.assertEqual(canvas.rows[12][left][0], "┘")

    def test_units_switch_and_shared_storage_visible(self):
        state = m.UIState()
        lines = str(m.disk_lines(fixture(), state))
        self.assertIn("9.30 GB", lines)
        self.assertIn("shared", lines)
        state.binary = True
        self.assertIn("8.66 GiB", str(m.disk_lines(fixture(), state)))

    def test_no_sum_across_network_interfaces(self):
        sample = fixture()
        sample["networks"]["bridge0"] = {"down": 8000000, "up": 1, "received": 99999999999, "sent": 0}
        state = m.UIState()
        lines = m.network_lines(sample, state, 80)
        self.assertEqual(state.interface, "eth0")
        self.assertIn("Download 1.50 MB/s", lines)

    def test_graph_peak_is_na_before_first_delta(self):
        sample = fixture()
        sample["networks"]["eth0"]["down"] = None
        state = m.UIState()
        state.accept(sample)
        self.assertIn("Download graph peak: N/A", m.network_lines(sample, state, 80))

    def test_sort_cpu_memory_and_na(self):
        sample = fixture()
        sample["processes"][0]["cpu"] = None
        sample["processes"][0]["rss"] = 999999999
        self.assertEqual(m.sorted_processes(sample, "cpu")[0]["pid"], 23)
        self.assertEqual(m.sorted_processes(sample, "memory")[0]["pid"], 0)


class CLI(unittest.TestCase):
    def test_no_tty_fails_with_guidance(self):
        result = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn("open a terminal", result.stderr)

    def test_snapshot_without_external_gpu(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--snapshot", "--no-gpu", "--interval", "0.5"],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        snapshot = json.loads(result.stdout)
        self.assertIn("processes", snapshot)
        self.assertIn("available", snapshot["memory"])

    def test_real_pty_resize_keys_and_terminal_restoration(self):
        for ending in (b"q", b"\x03", "SIGTERM"):
            with self.subTest(ending=ending), tempfile.TemporaryDirectory() as temp:
                master, slave = pty.openpty()
                original = termios.tcgetattr(slave)
                def size(rows, cols):
                    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
                size(40, 140)
                def session():
                    os.setsid()
                    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
                process = subprocess.Popen([sys.executable, str(SCRIPT), "--no-gpu", "--interval", "0.5"],
                    stdin=slave, stdout=slave, stderr=slave, env={**os.environ, "HOME": temp,
                    "TERM": "xterm-256color", "LC_ALL": "C.UTF-8"}, preexec_fn=session)
                output = bytearray()
                def pump(duration):
                    deadline = time.monotonic() + duration
                    while time.monotonic() < deadline:
                        if select.select([master], [], [], 0.025)[0]:
                            output.extend(os.read(master, 65536))
                try:
                    pump(0.7)
                    self.assertIsNone(process.poll())
                    os.write(master, b"2s 3un1c")
                    pump(0.2)
                    for rows, cols in ((24, 80), (12, 48), (8, 30), (40, 140)):
                        size(rows, cols)
                        os.kill(process.pid, signal.SIGWINCH)
                        pump(0.15)
                    os.write(master, b" ")
                    pump(0.1)
                    if ending == "SIGTERM":
                        os.kill(process.pid, signal.SIGTERM)
                    else:
                        os.write(master, ending)
                    pump(0.3)
                    process.wait(timeout=3)
                    self.assertEqual(process.returncode, 0, output.decode(errors="replace")[-1000:])
                    self.assertNotIn(b"Traceback", output)
                    self.assertIn(b"ARCHMIND MONITOR", output)
                    self.assertEqual(termios.tcgetattr(slave), original)
                    self.assertEqual(list(Path(temp).iterdir()), [], "monitor must not write to HOME")
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                    os.close(master)
                    os.close(slave)


if __name__ == "__main__":
    unittest.main(verbosity=2)
