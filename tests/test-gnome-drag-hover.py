#!/usr/bin/env python3
"""Isolated safety tests for the optional GNOME Drag Hover patch."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "payload/archmind/tools/configure-gnome-drag-hover.py"
UUID = "dash-to-dock@micxgx.gmail.com"


def dash_fixture(tag: str = "original") -> str:
    return f"""import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
// fixture: {tag}
class DockDash {{
    _init() {{
        this._appSystem = Shell.AppSystem.get_default();
        this.connect('destroy', this._onDestroy.bind(this));

    }}

    _onDestroy() {{
        this.iconAnimator.destroy();
        this._otherTimer = 0;
    }}

    handleDragOver(source, actor, x, y, time) {{
        return DND.DragMotionResult.CONTINUE;
    }}

    getAppIcons() {{
        return this._box.get_children();
    }}
}}
"""


class GnomeDragHoverTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="archmind-drag-hover-")
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.extension = self.home / ".local/share/gnome-shell/extensions" / UUID
        self.extension.mkdir(parents=True)
        self.dash = self.extension / "dash.js"
        self.original = dash_fixture()
        self.dash.write_text(self.original, encoding="utf-8")
        (self.extension / "metadata.json").write_text(
            json.dumps({"uuid": UUID, "version": 105}) + "\n", encoding="utf-8"
        )
        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "ARCHMIND_DATA_HOME": str(self.home / "ArchMind"),
                "ARCHMIND_DASH_TO_DOCK_DIR": str(self.extension),
                "ARCHMIND_TEST_SIMULATE": "1",
                "XDG_CURRENT_DESKTOP": "GNOME",
                "XDG_SESSION_TYPE": "wayland",
            }
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_script(
        self, *arguments: str, input_text: str | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", "-B", str(SCRIPT), *arguments],
            env=self.env,
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )

    def snapshots(self) -> list[Path]:
        root = self.home / "ArchMind/Installer-Backups/GNOME-Drag-Hover"
        return sorted(root.glob("apply-*")) if root.is_dir() else []

    def test_status_is_read_only_and_check_reports_not_configured(self) -> None:
        status = self.run_script("--status")
        check = self.run_script("--check")
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertIn("Not installed", status.stdout)
        self.assertIn("Ready", status.stdout)
        self.assertNotEqual(check.returncode, 0)
        self.assertFalse((self.home / "ArchMind").exists())
        self.assertEqual(self.dash.read_text(encoding="utf-8"), self.original)

    def test_install_is_atomic_idempotent_and_records_hashes(self) -> None:
        first = self.run_script("--install")
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
        patched = self.dash.read_text(encoding="utf-8")
        self.assertEqual(patched.count("ARCHMIND_DRAG_HOVER_PATCH"), 2)
        self.assertEqual(patched.count("ARCHMIND_WINDOW_HOVER_PATCH"), 2)
        self.assertIn("global.display.get_selection()", patched)
        self.assertIn("Main.activateWindow(targetWindow)", patched)
        self.assertNotIn("xdotool", patched)
        self.assertNotIn("wmctrl", patched)
        node = shutil.which("node")
        if node:
            module = self.base / "patched-dash.mjs"
            module.write_text(patched, encoding="utf-8")
            syntax = subprocess.run(
                [node, "--check", str(module)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(syntax.returncode, 0, syntax.stderr)
        snapshots = self.snapshots()
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(
            (snapshots[0] / "dash.js.original").read_text(encoding="utf-8"),
            self.original,
        )
        metadata = json.loads((snapshots[0] / "metadata.json").read_text(encoding="utf-8"))
        self.assertEqual(
            metadata["original_sha256"], hashlib.sha256(self.original.encode()).hexdigest()
        )
        self.assertEqual(
            metadata["patched_sha256"], hashlib.sha256(patched.encode()).hexdigest()
        )

        second = self.run_script("--reapply")
        self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
        self.assertEqual(len(self.snapshots()), 1)
        self.assertEqual(self.dash.read_text(encoding="utf-8"), patched)
        self.assertEqual(self.run_script("--check").returncode, 0)

    def test_remove_restores_the_exact_original(self) -> None:
        self.assertEqual(self.run_script("--install").returncode, 0)
        removed = self.run_script("--remove")
        self.assertEqual(removed.returncode, 0, removed.stderr + removed.stdout)
        self.assertEqual(self.dash.read_text(encoding="utf-8"), self.original)
        self.assertEqual(len(self.snapshots()), 1)
        restore_copies = list(
            (self.home / "ArchMind/Installer-Backups/GNOME-Drag-Hover").glob("restore-*")
        )
        self.assertEqual(len(restore_copies), 1)
        self.assertTrue((restore_copies[0] / "dash.js.before-restore").is_file())

    def test_update_is_never_overwritten_by_an_old_snapshot(self) -> None:
        self.assertEqual(self.run_script("--install").returncode, 0)
        updated = dash_fixture("updated-by-dash-to-dock")
        self.dash.write_text(updated, encoding="utf-8")
        (self.extension / "metadata.json").write_text(
            json.dumps({"uuid": UUID, "version": 106}) + "\n", encoding="utf-8"
        )

        status = self.run_script("--status")
        self.assertIn("Needs reapply after update", status.stdout)
        removed = self.run_script("--remove")
        self.assertEqual(removed.returncode, 0, removed.stderr + removed.stdout)
        self.assertEqual(self.dash.read_text(encoding="utf-8"), updated)

        reapplied = self.run_script("--reapply")
        self.assertEqual(reapplied.returncode, 0, reapplied.stderr + reapplied.stdout)
        self.assertEqual(len(self.snapshots()), 2)
        self.assertIn("updated-by-dash-to-dock", self.dash.read_text(encoding="utf-8"))

    def test_modified_patched_file_refuses_automatic_removal(self) -> None:
        self.assertEqual(self.run_script("--install").returncode, 0)
        modified = self.dash.read_text(encoding="utf-8") + "// manual change\n"
        self.dash.write_text(modified, encoding="utf-8")
        result = self.run_script("--remove")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No exact safety snapshot", result.stderr)
        self.assertEqual(self.dash.read_text(encoding="utf-8"), modified)

    def test_unknown_anchors_and_partial_patch_change_nothing(self) -> None:
        unsupported = self.original.replace(
            "this.connect('destroy', this._onDestroy.bind(this));", "this.connectObject();"
        )
        self.dash.write_text(unsupported, encoding="utf-8")
        result = self.run_script("--install")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported dash.js structure", result.stderr)
        self.assertEqual(self.dash.read_text(encoding="utf-8"), unsupported)
        self.assertEqual(self.snapshots(), [])

        partial = self.original + "// ARCHMIND_DRAG_HOVER_PATCH\n"
        self.dash.write_text(partial, encoding="utf-8")
        result = self.run_script("--install")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("partial or modified", result.stderr.lower())
        self.assertEqual(self.dash.read_text(encoding="utf-8"), partial)
        self.assertEqual(self.snapshots(), [])

    def test_symlink_target_is_refused(self) -> None:
        real = self.base / "real-dash.js"
        real.write_text(self.original, encoding="utf-8")
        self.dash.unlink()
        self.dash.symlink_to(real)
        result = self.run_script("--install")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symbolic-link", result.stderr)
        self.assertEqual(real.read_text(encoding="utf-8"), self.original)
        self.assertEqual(self.snapshots(), [])

    def test_unvalidated_version_requires_an_extra_decision(self) -> None:
        (self.extension / "metadata.json").write_text(
            json.dumps({"uuid": UUID, "version": 999}) + "\n", encoding="utf-8"
        )
        cancelled = self.run_script("--install", input_text="n\n")
        self.assertEqual(cancelled.returncode, 0, cancelled.stderr + cancelled.stdout)
        self.assertEqual(self.dash.read_text(encoding="utf-8"), self.original)
        self.assertEqual(self.snapshots(), [])

        accepted = self.run_script("--install", "--yes")
        self.assertEqual(accepted.returncode, 0, accepted.stderr + accepted.stdout)
        self.assertIn("ARCHMIND_DRAG_HOVER_PATCH", self.dash.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
