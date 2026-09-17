#!/usr/bin/env python3
"""PTY tests for confirmation, cancellation and failure; no real GUI required."""
import importlib.util
import os
import pty
import re
import select
import fcntl
import struct
import subprocess
import termios
import time
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("safety", Path(__file__).with_name("test-install-safety.py"))
safety = importlib.util.module_from_spec(spec)
spec.loader.exec_module(safety)


class RunFlowTests(unittest.TestCase):
    setUp = safety.SafetyTests.setUp
    tearDown = safety.SafetyTests.tearDown
    manifest = safety.SafetyTests.manifest
    run_cmd = safety.SafetyTests.run_cmd
    write = safety.SafetyTests.write
    mock = safety.SafetyTests.mock

    def build(self):
        launcher = self.package / "payload/toolkit/bin/archmind-console"
        launcher.write_text('#!/bin/bash\nprintf "AFI_OPENED\\n"\npwd > "$HOME/afi-started"\n')
        if self.simulated:
            template = self.package / "installer/ArchMind-Installer.run.in"
            template.write_text(template.read_text().replace("(( EUID != 0 ))", "(( 1 ))"))
        self.manifest()
        self.run_file = self.root / "instalador com espaços.run"
        self.run_cmd("bash", self.package / "installer/build-run-installer.sh", self.run_file)

    def interactive(self, replies, command=None, columns=80):
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, columns, 0, 0))
        environment = dict(self.env, ARCHMIND_RUN_IN_TERMINAL="1")
        process = subprocess.Popen(command or ["bash", str(self.run_file)], stdin=slave, stdout=slave,
                                   stderr=slave, env=environment, cwd=self.home, start_new_session=True)
        os.close(slave)
        output = b""
        sent = set()
        deadline = time.monotonic() + 35
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
                for prompt, reply in replies.items():
                    if prompt not in sent and prompt.encode() in output:
                        os.write(master, reply.encode())
                        sent.add(prompt)
                if process.poll() is not None and not ready:
                    break
            else:
                self.fail("PTY timed out: " + output.decode(errors="replace"))
            code = process.wait(timeout=3)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
        return code, output.decode(errors="replace")

    def test_success_opens_only_installed_console(self):
        self.build()
        started = time.monotonic()
        code, output = self.interactive({"according to this plan? [y/N]:": "y\n"})
        self.assertGreaterEqual(time.monotonic() - started, 5.0)
        self.assertEqual(code, 0, output)
        self.assertIn("AFI_OPENED", output)
        values = [int(value) for value in re.findall(r"(\d{1,3})%", output)]
        self.assertEqual(values, sorted(values))
        for milestone in (0, 15, 30, 50, 75, 95, 100):
            self.assertIn(milestone, values)
        self.assertLess(output.index("100%"), output.index("AFI_OPENED"))
        self.assertEqual((self.home / "afi-started").read_text().strip(), str(self.home))
        self.assertTrue((self.home / "ArchMind/System/Core").is_dir())

    def test_cancel_does_not_install_or_open(self):
        self.build()
        code, output = self.interactive({"according to this plan? [y/N]:": "n\n"})
        self.assertEqual(code, 0, output)
        self.assertIn("cancelled", output)
        self.assertNotIn("minimum display time", output)
        self.assertFalse((self.home / "ArchMind").exists())
        self.assertFalse((self.home / "afi-started").exists())

    def test_install_failure_never_opens_console(self):
        self.build()
        self.mock("chmod", 'case "$*" in *archmind-execute-terminal.desktop*) exit 23;; esac\nexec /usr/bin/chmod "$@"\n')
        code, output = self.interactive({"according to this plan? [y/N]:": "y\n", "Press Enter to close...": "\n"})
        self.assertEqual(code, 23, output)
        self.assertNotIn("AFI_OPENED", output)
        self.assertNotIn("100%", output)
        self.assertIn("restoring the previous state", output)
        self.assertFalse((self.home / "afi-started").exists())
        self.assertFalse((self.home / "ArchMind/System/Core").exists())

    def test_progress_fits_narrow_terminal(self):
        self.build()
        code, output = self.interactive({"according to this plan? [y/N]:": "y\n"}, columns=32)
        self.assertEqual(code, 0, output)
        ansi = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
        frames = [ansi.sub("", frame).strip("\n") for frame in output.split("\r")]
        bars = [frame for frame in frames if re.match(r"^\[[█░]+\] +\d+%", frame)]
        self.assertTrue(bars, output)
        self.assertTrue(all(len(frame.split("\n", 1)[0]) < 32 for frame in bars), bars)

    def test_no_progress_flag(self):
        code, output = self.interactive({}, command=["bash", str(self.installer), "--no-progress"])
        self.assertEqual(code, 0, output)
        self.assertNotIn("minimum display time", output)
        self.assertNotIn("100%", output)

    def test_headless_checks_and_extract_no_overwrite(self):
        self.build()
        self.mock("gnome-terminal", 'touch "$HOME/terminal-was-called"\nexit 1\n')
        self.run_cmd("bash", self.run_file, "--check")
        self.assertFalse((self.home / "terminal-was-called").exists())
        destination = self.home / "extração"
        self.run_cmd("bash", self.run_file, "--extract", destination)
        self.run_cmd("bash", self.run_file, "--extract", destination, code=1)
        self.assertFalse((self.home / "terminal-was-called").exists())
        with self.run_file.open("ab") as stream:
            stream.write(b"CORRUPTED")
        result = self.run_cmd("bash", self.run_file, "--check", code=1)
        self.assertIn("integrity", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
