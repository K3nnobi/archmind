#!/usr/bin/env python3
"""Isolated tests for ArchMind 1.5.18 Maintenance Center."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import unittest


PACKAGE = Path(__file__).resolve().parents[1]
TOOLS = PACKAGE / "payload/archmind/tools"


class MaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp())
        self.home = self.temp / "home"
        self.data = self.home / "ArchMind"
        self.bin = self.temp / "bin"
        self.home.mkdir()
        self.bin.mkdir()
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "ARCHMIND_DATA_HOME": str(self.data),
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "ARCHMIND_TEST_SIMULATE": "1",
        }

    def tearDown(self):
        shutil.rmtree(self.temp)

    def run_tool(self, name, *args, input_text=None, check=True, env=None):
        result = subprocess.run(
            ["python3", "-B", str(TOOLS / name), *args],
            input=input_text,
            capture_output=True,
            text=True,
            env=env or self.env,
            check=False,
        )
        if check and result.returncode:
            self.fail(f"{name} failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
        return result

    def executable(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
        path.chmod(0o755)
        return path

    def test_tasks_are_private_and_resolvable(self):
        self.run_tool(
            "pending-tasks.py", "--add", "reboot-required", "--title", "Restart",
            "--severity", "critical", "--detail", "Kernel changed",
        )
        state = self.data / "State/Maintenance/pending-tasks.json"
        self.assertEqual(state.stat().st_mode & 0o777, 0o600)
        summary = self.run_tool("pending-tasks.py", "--summary").stdout.strip()
        self.assertEqual(summary, "1 1")
        self.run_tool("pending-tasks.py", "--resolve", "reboot-required")
        self.assertEqual(self.run_tool("pending-tasks.py", "--summary").stdout.strip(), "0 0")

    def test_operating_profile_is_backed_up_configuration(self):
        self.run_tool("operating-profiles.py", "--set", "quiet")
        profile = self.data / "Config/Maintenance/operating-profile.json"
        self.assertTrue(profile.is_file())
        self.assertEqual(self.run_tool("operating-profiles.py", "--interval").stdout.strip(), "5")
        self.run_tool("operating-profiles.py", "--set", "diagnostic")
        self.assertEqual(self.run_tool("operating-profiles.py", "--interval").stdout.strip(), "0.5")

    def test_hardware_detection_controls_capabilities(self):
        root = self.temp / "root"
        (root / "sys/class/drm/card0/device").mkdir(parents=True)
        (root / "sys/class/drm/card0/device/vendor").write_text("0x10de\n")
        (root / "sys/firmware/efi").mkdir(parents=True)
        (root / "etc/default").mkdir(parents=True)
        (root / "etc/default/grub").write_text('GRUB_CMDLINE_LINUX_DEFAULT="quiet"\n')
        (root / "etc").mkdir(exist_ok=True)
        (root / "etc/mkinitcpio.conf").write_text("HOOKS=(base udev autodetect)\n")
        (root / "usr/bin").mkdir(parents=True)
        (root / "usr/bin/gnome-shell").write_text("")
        env = {**self.env, "ARCHMIND_TEST_ROOT": str(root), "XDG_CURRENT_DESKTOP": "GNOME"}
        profile = json.loads(self.run_tool("hardware-profile.py", "--json", env=env).stdout)
        self.assertTrue(profile["capabilities"]["nvidia_vibrance"])
        self.assertTrue(profile["capabilities"]["plymouth_patch"])
        self.assertTrue(profile["capabilities"]["gnome_integrations"])

        code = 'ARCHMIND_ROOT="$1"; source "$1/core/afi/screens.zsh"; afi_load_screen install; print -rl -- "${AFI_SCREEN_ENTRIES[@]}"'
        menu = subprocess.run(
            ["zsh", "-dfc", code, "test", str(PACKAGE / "payload/archmind")],
            capture_output=True, text=True, env=env, check=True,
        ).stdout
        self.assertIn("NVIDIA Vibrance", menu)
        self.assertIn("Plymouth / Boot Visual", menu)
        self.assertIn("GNOME Visual Integration", menu)

        empty_root = self.temp / "empty-root"
        empty_root.mkdir()
        hidden_env = {**self.env, "ARCHMIND_TEST_ROOT": str(empty_root), "XDG_CURRENT_DESKTOP": "Other"}
        hidden_menu = subprocess.run(
            ["zsh", "-dfc", code, "test", str(PACKAGE / "payload/archmind")],
            capture_output=True, text=True, env=hidden_env, check=True,
        ).stdout
        self.assertNotIn("NVIDIA Vibrance", hidden_menu)
        self.assertNotIn("Plymouth / Boot Visual", hidden_menu)
        self.assertNotIn("GNOME Visual Integration", hidden_menu)

    def test_guardian_detects_updates_done_outside_archmind(self):
        package_file = self.temp / "packages"
        package_file.write_text("linux-lts 1\ngrub 1\nmutter 1\ngnome-rounded-blur 1\n")
        self.executable(
            "pacman",
            'if [[ "$1" == "-Q" && $# -eq 1 ]]; then cat "$PACKAGE_FILE"; exit 0; fi\n'
            'if [[ "$1" == "-Q" ]]; then grep -q "^$2 " "$PACKAGE_FILE"; exit $?; fi\nexit 1\n',
        )
        env = {**self.env, "PACKAGE_FILE": str(package_file)}
        self.run_tool("update-guardian.py", "--baseline-only", env=env)
        package_file.write_text("linux-lts 2\ngrub 2\nmutter 2\ngnome-rounded-blur 1\n")
        self.run_tool("update-guardian.py", "--baseline-only", env=env)
        tasks = json.loads(self.run_tool("pending-tasks.py", "--json", env=env).stdout)
        identifiers = {task["id"] for task in tasks if not task["resolved"]}
        self.assertIn("reboot-required", identifiers)
        self.assertIn("plymouth-reapply", identifiers)
        self.assertIn("gnome-session-restart", identifiers)
        self.assertIn("rounded-blur-rebuild", identifiers)

    def test_cleanup_cancel_is_read_only_and_thumbnail_cleanup_is_scoped(self):
        thumbnails = self.home / ".cache/thumbnails/normal"
        thumbnails.mkdir(parents=True)
        cached = thumbnails / "cached.png"
        cached.write_bytes(b"cache")
        outside = self.home / "outside.png"
        outside.write_bytes(b"keep")
        (thumbnails / "outside-link.png").symlink_to(outside)
        self.run_tool("cleanup-audit.py", "--interactive", input_text="0\n")
        self.assertTrue(cached.exists())
        self.run_tool("cleanup-audit.py", "--interactive", input_text="3\nCLEAN\n")
        self.assertFalse(cached.exists())
        self.assertEqual(outside.read_bytes(), b"keep")

    def test_backup_catalog_reads_manifest_without_extracting(self):
        backup_dir = self.data / "Backups"
        source = self.temp / "backup-source"
        (source / "packages").mkdir(parents=True)
        (source / "manifest.json").write_text(json.dumps({
            "format": "archmind", "version": "2.0.0", "mode": "complete",
            "created": "2026-09-10T12:00:00-03:00", "hostname": "example-host", "user": "testuser",
        }))
        (source / "packages/pacman-all.txt").write_text("linux-lts 1\nfirefox 1\n")
        (source / "checksums.sha256").write_text("catalog\n")
        backup_dir.mkdir(parents=True)
        archive = backup_dir / "sample.archmind"
        with tarfile.open(archive, "w:gz") as tar:
            for path in source.rglob("*"):
                tar.add(path, arcname=path.relative_to(source))
        self.executable("pacman", '[[ "$1" == "-Qq" ]] && printf "linux-lts\\n"\n')
        env = {**self.env, "ARCHMIND_BACKUP_DIR": str(backup_dir)}
        output = self.run_tool("backup-catalog.py", "--latest", env=env).stdout
        self.assertIn("example-host", output)
        self.assertIn("Packages recorded .. 2", output)
        self.assertIn("Missing locally .... 1", output)

    def test_rollback_center_only_catalogs_unknown_snapshots(self):
        snapshot = self.data / "Installer-Backups/archmind-before-1.5.14-test"
        snapshot.mkdir(parents=True)
        (snapshot / "file").write_bytes(b"safe")
        wine_snapshot = self.data / "Installer-Backups/Wine/default-pre-compat-test"
        wine_snapshot.mkdir(parents=True)
        (wine_snapshot / "system.reg").write_bytes(b"safe-registry")
        drag_snapshot = self.data / "Installer-Backups/GNOME-Drag-Hover/apply-test"
        drag_snapshot.mkdir(parents=True)
        (drag_snapshot / "dash.js.original").write_bytes(b"safe-dash")
        output = self.run_tool("rollback-center.py").stdout
        self.assertIn("ArchMind installer", output)
        self.assertIn("Wine Compatibility Pack", output)
        self.assertIn("GNOME Drag Hover", output)
        self.assertIn("not restored blindly", output)
        self.assertEqual((snapshot / "file").read_bytes(), b"safe")
        self.assertEqual((wine_snapshot / "system.reg").read_bytes(), b"safe-registry")
        self.assertEqual((drag_snapshot / "dash.js.original").read_bytes(), b"safe-dash")


if __name__ == "__main__":
    unittest.main(verbosity=2)
