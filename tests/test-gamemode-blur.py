#!/usr/bin/env python3
"""Isolated tests for the ArchMind GameMode + GNOME extension hooks."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "payload/archmind/tools/gamemode-blur.sh"
CONFIGURE = ROOT / "payload/archmind/tools/configure-gamemode-blur.sh"
UUID = "blur-my-shell@aunetx"


class GameModeBlurTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="archmind-gamemode-test-")
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.runtime = self.base / "runtime"
        self.mock_bin = self.base / "bin"
        self.state = self.base / "enabled.txt"
        self.installed = self.base / "installed.txt"
        self.calls = self.base / "calls.txt"
        for path in (self.home, self.runtime, self.mock_bin):
            path.mkdir(parents=True)
        self.installed.write_text(f"{UUID}\n", encoding="utf-8")
        self.state.write_text(f"{UUID}\n", encoding="utf-8")
        self.calls.write_text("", encoding="utf-8")
        self._write_mocks()
        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.home / ".config"),
                "XDG_RUNTIME_DIR": str(self.runtime),
                "ARCHMIND_DATA_HOME": str(self.home / "ArchMind"),
                "ARCHMIND_GAMEMODE_HOOK": str(HOOK),
                "ARCHMIND_TEST_SIMULATE": "1",
                "MOCK_EXT_STATE": str(self.state),
                "MOCK_EXT_INSTALLED": str(self.installed),
                "MOCK_CALLS": str(self.calls),
                "MOCK_HOOK": str(HOOK),
                "PATH": f"{self.mock_bin}:{os.environ.get('PATH', '')}",
            }
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _write_executable(self, name: str, content: str) -> None:
        target = self.mock_bin / name
        target.write_text(content, encoding="utf-8")
        target.chmod(0o755)

    def _write_mocks(self) -> None:
        self._write_executable(
            "gnome-extensions",
            """#!/usr/bin/env bash
set -eu
case "${1:-}:${2:-}" in
  list:--enabled) cat "$MOCK_EXT_STATE" ;;
  list:*) cat "$MOCK_EXT_INSTALLED" ;;
  disable:*)
    grep -Fxv -- "$2" "$MOCK_EXT_STATE" > "$MOCK_EXT_STATE.tmp" || true
    mv -- "$MOCK_EXT_STATE.tmp" "$MOCK_EXT_STATE"
    printf 'disable %s\n' "$2" >> "$MOCK_CALLS"
    ;;
  enable:*)
    grep -Fxq -- "$2" "$MOCK_EXT_STATE" || printf '%s\n' "$2" >> "$MOCK_EXT_STATE"
    printf 'enable %s\n' "$2" >> "$MOCK_CALLS"
    ;;
  *) exit 2 ;;
esac
""",
        )
        self._write_executable(
            "pacman",
            """#!/usr/bin/env bash
[[ "${1:-}" == "-Q" || "${1:-}" == "-Qq" ]] && exit 0
exit 2
""",
        )
        self._write_executable(
            "gamemoded",
            """#!/usr/bin/env bash
[[ "${1:-}" == "-s" ]] && { printf 'gamemode is inactive\n'; exit 0; }
exit 2
""",
        )
        self._write_executable(
            "systemctl",
            """#!/usr/bin/env bash
[[ "${1:-}" == "--user" ]] || exit 2
[[ "${2:-}" == "cat" || "${2:-}" == "restart" ]]
""",
        )
        self._write_executable(
            "gamemoderun",
            """#!/usr/bin/env bash
set -eu
"$MOCK_HOOK" start
"$@"
status=$?
"$MOCK_HOOK" end
exit "$status"
""",
        )

    def run_script(self, script: Path, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(script), *args],
            env=self.env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )

    def enabled(self) -> list[str]:
        return [line for line in self.state.read_text(encoding="utf-8").splitlines() if line]

    def test_hook_restores_only_an_extension_that_was_enabled(self) -> None:
        first = self.run_script(HOOK, "start")
        second = self.run_script(HOOK, "start")
        end = self.run_script(HOOK, "end")
        self.assertEqual((first.returncode, second.returncode, end.returncode), (0, 0, 0))
        self.assertEqual(self.enabled(), [UUID])
        calls = self.calls.read_text(encoding="utf-8").splitlines()
        self.assertEqual(calls, [f"disable {UUID}", f"enable {UUID}"])

        self.state.write_text("", encoding="utf-8")
        self.calls.write_text("", encoding="utf-8")
        self.assertEqual(self.run_script(HOOK, "start").returncode, 0)
        self.assertEqual(self.run_script(HOOK, "end").returncode, 0)
        self.assertEqual(self.enabled(), [])
        self.assertEqual(self.calls.read_text(encoding="utf-8"), "")

    def test_apply_preserves_other_hooks_and_is_idempotent(self) -> None:
        config = self.home / ".config/gamemode.ini"
        config.parent.mkdir(parents=True)
        config.write_text(
            "[general]\nrenice=5\n\n[custom]\n"
            "start=notify-send Existing\n"
            "start=$HOME/.local/bin/gamemode-blur start\n"
            "end=$HOME/.local/bin/gamemode-blur end\n",
            encoding="utf-8",
        )
        first = self.run_script(CONFIGURE, "--apply")
        self.assertEqual(first.returncode, 0, first.stderr)
        first_content = config.read_text(encoding="utf-8")
        backups = list((self.home / "ArchMind/Installer-Backups").glob("gamemode.ini-before-*"))

        second = self.run_script(CONFIGURE, "--apply")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(config.read_text(encoding="utf-8"), first_content)
        self.assertEqual(
            len(list((self.home / "ArchMind/Installer-Backups").glob("gamemode.ini-before-*"))),
            len(backups),
        )
        self.assertIn("start=notify-send Existing", first_content)
        self.assertNotIn("$HOME/.local/bin/gamemode-blur", first_content)
        self.assertEqual(first_content.count("; BEGIN ARCHMIND GAMEMODE BLUR"), 1)
        self.assertIn(f"start='{HOOK}' start", first_content)
        self.assertIn(f"end='{HOOK}' end", first_content)

    def test_end_to_end_test_uses_gamemoderun_and_restores_blur(self) -> None:
        self.assertEqual(self.run_script(CONFIGURE, "--apply").returncode, 0)
        result = self.run_script(CONFIGURE, "--test")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("Validated", result.stdout)
        self.assertEqual(self.enabled(), [UUID])
        self.assertEqual(
            self.calls.read_text(encoding="utf-8").splitlines(),
            [f"disable {UUID}", f"enable {UUID}"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
