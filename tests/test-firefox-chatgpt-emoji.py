#!/usr/bin/env python3
"""Exercise real file preservation, profile selection, idempotence and rollback."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "payload/archmind/tools/configure-firefox-chatgpt-emoji.py"
MARKER = "/* ARCHMIND-CHATGPT-EMOJI-BEGIN */"


class EmojiFixTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "home"
        self.firefox = self.home / ".mozilla/firefox"
        self.selected = self.firefox / "one.default-release"
        self.other = self.firefox / "two.testing"
        self.selected.mkdir(parents=True)
        self.other.mkdir()
        (self.firefox / "profiles.ini").write_text(
            "[Profile0]\nName=default-release\nIsRelative=1\nPath=one.default-release\nDefault=1\n"
            "[Profile1]\nName=test\nIsRelative=1\nPath=two.testing\n",
            encoding="utf-8",
        )
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        for name, body in {
            "firefox": "exit 0",
            "pacman": "exit 0",
            "fc-cache": "exit 0",
            "fc-match": "printf 'Noto Color Emoji\\n'",
        }.items():
            file = self.bin / name
            file.write_text("#!/bin/sh\n" + body + "\n")
            file.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=f"{self.bin}:/usr/bin:/bin", ARCHMIND_TEST_SIMULATE="1")

    def run_patch(self, option, code=0):
        result = subprocess.run(["python3", "-B", str(SCRIPT), option], env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def test_preserves_customizations_and_restores_false(self):
        css = self.selected / "chrome/userContent.css"
        css.parent.mkdir()
        css.write_text("body { color: red; }\n")
        js = self.selected / "user.js"
        js.write_text('user_pref("another.setting", 42);\n'
                      'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", false);\n')
        original_css, original_js = css.read_text(), js.read_text()
        self.run_patch("--apply")
        self.assertEqual(css.read_text().count(MARKER), 1)
        self.assertIn('"OpenAI Sans", "Noto Color Emoji", "Adwaita Sans"', css.read_text())
        self.assertIn("body { color: red; }", css.read_text())
        self.assertEqual(js.read_text().count("toolkit.legacyUserProfileCustomizations.stylesheets"), 1)
        self.assertIn("true);", js.read_text())
        self.assertFalse((self.other / "user.js").exists())
        safety = self.home / "ArchMind/Backups/Safety/firefox-chatgpt-emoji"
        self.assertEqual(len(list(safety.rglob("userContent.css.bak"))), 1)
        self.assertEqual(len(list(safety.rglob("user.js.bak"))), 1)
        self.run_patch("--apply")
        self.assertEqual(css.read_text().count(MARKER), 1)
        self.assertEqual(len(list(safety.rglob("userContent.css.bak"))), 1)
        self.run_patch("--remove")
        self.assertEqual(css.read_text(), original_css)
        self.assertIn('user_pref("another.setting", 42);', js.read_text())
        self.assertIn('user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", false);', js.read_text())
        self.assertEqual(js.read_text(), original_js)

    def test_new_files_removed_and_existing_true_preserved(self):
        self.run_patch("--apply")
        self.assertTrue((self.selected / "chrome/userContent.css").exists())
        self.run_patch("--remove")
        self.assertFalse((self.selected / "chrome/userContent.css").exists())
        self.assertFalse((self.selected / "user.js").exists())
        js = self.selected / "user.js"
        js.write_text('user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);\n')
        self.run_patch("--apply")
        self.run_patch("--remove")
        self.assertIn("true);", js.read_text())

    def test_refuses_unbalanced_markers_without_editing(self):
        css = self.selected / "chrome/userContent.css"
        css.parent.mkdir()
        css.write_text(MARKER + "\nuser text")
        self.run_patch("--apply", code=1)
        self.assertEqual(css.read_text(), MARKER + "\nuser text")
        self.assertFalse((self.selected / "user.js").exists())

    def test_rejects_profile_symlink(self):
        (self.firefox / "profiles.ini").write_text(
            "[Profile0]\nPath=escape.default-release\nIsRelative=1\nDefault=1\n"
        )
        (self.firefox / "escape.default-release").symlink_to(self.other, target_is_directory=True)
        self.run_patch("--apply", code=1)
        self.assertFalse((self.other / "user.js").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
