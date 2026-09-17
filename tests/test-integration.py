#!/usr/bin/env python3
"""Isolated 1.5.10 tests: never contact repositories or install packages."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "payload/archmind/tools"
sys.path.insert(0, str(TOOLS))


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), TOOLS / (name + ".py"))
    obj = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = obj
    spec.loader.exec_module(obj)
    return obj


reports, updates, storage = module("doctor-report"), module("system-updates"), module("storage-info")


class Reports(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="archmind-report-test-")
        self.home = Path(self.temp.name)
        self.env = patch.dict(os.environ, {"HOME": str(self.home), "ARCHMIND_DATA_HOME": str(self.home / "ArchMind")})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.temp.cleanup()

    def test_view_before_diagnosis_does_not_create_files(self):
        self.assertIn("Run Quick Diagnosis", reports.latest_report())
        self.assertEqual(list(self.home.iterdir()), [])

    def test_saved_reports_are_private_and_persistent(self):
        first = reports.save_report("Quick", "1.5.10", "Healthy\n")
        second = reports.save_report("Full", "1.5.10", "Unavailable\n")
        self.assertIn("Unavailable", reports.latest_report())
        self.assertIn("Healthy", first.read_text())
        self.assertEqual(stat.S_IMODE(second.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(second.parent.stat().st_mode), 0o700)
        self.assertFalse(list(second.parent.glob(".pending-*")))
        self.assertIn("Recorded:", second.read_text())

    def test_failed_publish_preserves_previous_report(self):
        reports.save_report("Quick", "1.5.10", "original")
        with patch.object(reports.os, "link", side_effect=OSError("simulated failure")):
            with self.assertRaises(OSError):
                reports.save_report("Quick", "1.5.10", "incomplete")
        self.assertIn("original", reports.latest_report())
        self.assertEqual(len(list((self.home / "ArchMind/Logs/Doctor").iterdir())), 1)

    def test_symlink_directory_is_refused(self):
        outside = self.home / "elsewhere"
        outside.mkdir()
        (self.home / "ArchMind").symlink_to(outside)
        with self.assertRaises(OSError):
            reports.save_report("Quick", "1.5.10", "data")
        self.assertEqual(list(outside.iterdir()), [])

    def test_latest_symlink_or_fifo_is_not_read(self):
        saved = reports.save_report("Quick", "1.5.10", "data")
        saved.unlink()  # only our temporary fixture
        saved.symlink_to("/etc/passwd")
        with self.assertRaises(OSError):
            reports.latest_report()
        saved.unlink()
        os.mkfifo(saved)
        with self.assertRaises(ValueError):
            reports.latest_report()

    def test_empty_and_control_text(self):
        with self.assertRaises(ValueError):
            reports.save_report("Quick", "1.5.10", "")
        saved = reports.save_report("Quick", "1.5.10", "hello\x1b[2J\nworld\x00")
        self.assertNotIn("\x1b", saved.read_text())
        self.assertNotIn("\x00", saved.read_text())

    def test_export_import_additive_and_no_home_scatter(self):
        saved = reports.save_report("Quick", "1.5.10", "backed up")
        backup = self.home / "backup"
        self.assertEqual(reports.transfer_reports(backup), 1)
        second_home = self.home / "second home"
        second_home.mkdir()
        with patch.dict(os.environ, {"HOME": str(second_home), "ARCHMIND_DATA_HOME": str(second_home / "ArchMind")}):
            self.assertEqual(reports.transfer_reports(backup, True), 1)
            self.assertEqual(reports.transfer_reports(backup, True), 0)
            self.assertIn("backed up", reports.latest_report())
            restored = second_home / "ArchMind/Logs/Doctor" / saved.name
            self.assertEqual(restored.read_bytes(), saved.read_bytes())
            self.assertEqual([p.name for p in second_home.iterdir()], ["ArchMind"])

    def test_group_writable_directory_refused(self):
        root = self.home / "ArchMind"
        root.mkdir(mode=0o777)
        root.chmod(0o777)
        with self.assertRaises(PermissionError):
            reports.save_report("Quick", "1.5.10", "data")


class Updates(unittest.TestCase):
    def results(self, ok=True):
        return {name: {"ok": ok, "lines": ["test 1 -> 2"], "message": "test"}
                for name in ("Official repositories", "AUR", "Flatpak")}

    def test_exit_codes_never_turn_failure_into_zero_updates(self):
        for code, out, err, expected in ((0, "pkg 1 -> 2\n", "", True), (2, "", "", True),
                                         (1, "", "network failed", False), (2, "", "failure", False)):
            with patch.object(updates.subprocess, "run", return_value=subprocess.CompletedProcess([], code, out, err)):
                self.assertEqual(updates.query(["checkupdates"], empty_code=2)["ok"], expected)

    def test_timeout_is_unavailable(self):
        with patch.object(updates.subprocess, "run", side_effect=subprocess.TimeoutExpired("check", 90)):
            self.assertFalse(updates.query(["checkupdates"])["ok"])

    def test_check_uses_only_private_database_and_read_commands(self):
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, {"HOME": home, "ARCHMIND_DATA_HOME": home + "/ArchMind"}):
            def run(command, **kwargs):
                self.assertNotIn("sudo", command)
                self.assertNotIn("-Syu", command)
                self.assertNotIn("-Sy", command)
                if command[0] == "checkupdates":
                    self.assertTrue(kwargs["env"]["CHECKUPDATES_DB"].startswith(home + "/ArchMind/Temp/Updates/check-"))
                return subprocess.CompletedProcess(command, 0, "", "")
            with patch.object(updates.shutil, "which", side_effect=lambda name: "/mock/" + name), patch.object(updates.subprocess, "run", side_effect=run) as call:
                result, helper = updates.collect_updates()
            self.assertEqual(call.call_count, 3)
            self.assertTrue(result["Official repositories"]["ok"])
            self.assertEqual(helper, "yay")
            self.assertEqual(list(Path(home + "/ArchMind/Temp/Updates").iterdir()), [])

    def test_missing_tools_not_implicitly_installed(self):
        with patch.object(updates.shutil, "which", return_value=None), patch.object(updates.subprocess, "run") as run:
            result, _ = updates.collect_updates()
        run.assert_not_called()
        self.assertFalse(result["Official repositories"]["ok"])
        self.assertIn("pacman-contrib", result["Official repositories"]["message"])

    def interactive(self, answers, results=None, code=0):
        values = iter(answers)
        with contextlib.redirect_stdout(io.StringIO()) as output, \
             patch.object(updates.os, "geteuid", return_value=1000), \
             patch.object(updates.sys.stdin, "isatty", return_value=True), \
             patch.object(updates.sys.stdout, "isatty", return_value=True), \
             patch.object(updates.shutil, "which", side_effect=lambda name: "/mock/" + name), \
             patch.object(updates.subprocess, "run", return_value=subprocess.CompletedProcess([], code)) as run:
            result = updates.interactive(results or self.results(), "yay", lambda _: next(values))
        return result, run, output.getvalue()

    def test_cancel_and_failed_check_never_upgrade(self):
        for replies, result in (([""], self.results()), (["1", "yes"], self.results()),
                                 (["1"], self.results(False))):
            _, run, output = self.interactive(replies, result)
            run.assert_not_called()

    def test_only_explicit_confirmation_runs_selected_command(self):
        for choice, command in (("1", ["sudo", "pacman", "-Syu"]), ("2", ["yay", "-Syu"]), ("3", ["flatpak", "update"])):
            result, run, _ = self.interactive([choice, "UPDATE"])
            self.assertEqual(result, 0)
            called_commands = [call.args[0] for call in run.call_args_list]
            self.assertIn(command, called_commands)
            self.assertNotIn("--noconfirm", command)

    def test_failed_transaction_not_success(self):
        result, _, output = self.interactive(["1", "UPDATE"], code=9)
        self.assertEqual(result, 9)
        self.assertNotIn("finished successfully", output)

    def test_root_cannot_upgrade(self):
        with patch.object(updates.os, "geteuid", return_value=0), patch.object(updates.subprocess, "run") as run, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(updates.interactive(self.results(), "yay"), 1)
        run.assert_not_called()


class Integration(unittest.TestCase):
    def test_storage_explicit_units_and_shared_group(self):
        data = [{"paths": ["/", "Home"], "fs": "btrfs", "total": 119000000000,
                 "used": 109700000000, "available": 9300000000, "reserved": 0}]
        with patch.object(storage.monitor, "storage_info", return_value=data):
            output = storage.collect()
        self.assertIn("9.30 GB", output)
        self.assertIn("8.66 GiB", output)
        self.assertIn("shared filesystem", output)
        self.assertEqual(output.count("Filesystem:"), 1)

    def test_doctor_failed_query_and_full_summary(self):
        source = ROOT / "payload/archmind/services/doctor.zsh"
        code = r'''
source "$1"
doctor_check_internet() { print OK; }
doctor_check_dns() { print OK; }
doctor_check_pacman_lock() { print OK; }
doctor_check_pacman_database() { print OK; }
doctor_check_mirrorlist() { print OK; }
doctor_check_disk() { print OK; }
doctor_check_failed_services() { print 'Unavailable'; return 1; }
doctor_check_pipewire() { print 'Unavailable'; return 1; }
doctor_check_plymouth_patch() { print 'Not configured (optional)'; }
doctor_check_maintenance_tasks() { print '0 pending'; }
doctor_package_count() { print 0; }
doctor_collect_full
print -rl -- "${DOCTOR_FULL_LINES[@]}"
'''
        result = subprocess.run(["zsh", "-dfc", code, "test", str(source)], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("2 warning(s)", result.stdout)
        self.assertNotIn("Healthy", result.stdout)
        self.assertEqual(result.stdout.count("Result ...."), 1)

    def test_doctor_flags_stale_plymouth_patch(self):
        source = ROOT / "payload/archmind/services/doctor.zsh"
        with tempfile.TemporaryDirectory(prefix="archmind-plymouth-doctor-") as root:
            home = Path(root) / "home"
            helper = Path(root) / "core/patches/plymouth/plymouth-patch.sh"
            (home / "ArchMind/Config/Patches/Plymouth").mkdir(parents=True)
            helper.parent.mkdir(parents=True)
            (home / "ArchMind/Config/Patches/Plymouth/state.conf").write_text("FORMAT=1\n")
            helper.write_text("#!/usr/bin/env bash\nexit 1\n")
            helper.chmod(0o755)
            code = 'source "$1"; ARCHMIND_ROOT="$2"; doctor_check_plymouth_patch'
            result = subprocess.run(
                ["zsh", "-dfc", code, "test", str(source), str(Path(root) / "core")],
                env={**os.environ, "HOME": str(home)},
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("Needs reapply", result.stdout)

    def test_doctor_missing_systemctl_is_unavailable(self):
        source = ROOT / "payload/archmind/services/doctor.zsh"
        code = 'source "$1"; path=(); doctor_check_failed_services'
        result = subprocess.run(["zsh", "-dfc", code, "test", str(source)], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Unavailable", result.stdout)

    def test_monitor_is_identical_to_approved_prototype(self):
        import hashlib
        self.assertEqual(hashlib.sha256((TOOLS / "live-monitor.py").read_bytes()).hexdigest(),
                         "0269cea004257c97de1d009bdbef95424c0250119329307b3b1b2e5e92776991")

    def test_view_report_does_not_run_diagnosis(self):
        actions = (ROOT / "payload/archmind/core/afi/actions.zsh").read_text()
        case = actions.split("doctor-report)", 1)[1].split(";;", 1)[0]
        self.assertIn("doctor_view_report", case)
        self.assertNotIn("doctor_collect", case)

    def test_afi_translation_audit(self):
        audit = module("translation-audit")
        findings = []
        for folder in ("core/afi", "services", "console"):
            for path in (ROOT / "payload/archmind" / folder).glob("*.zsh"):
                for index, line in enumerate(path.read_text().splitlines(), 1):
                    if not line.lstrip().startswith("#") and audit.line_reasons(line):
                        findings.append(f"{path.name}:{index}: {line}")
        self.assertEqual(findings, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
