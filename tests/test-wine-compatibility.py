#!/usr/bin/env python3
"""Isolated tests for the optional ArchMind Wine Compatibility Pack."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "payload/archmind/tools/configure-wine-compatibility.sh"


class WineCompatibilityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="archmind-wine-pack-")
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.bin = self.base / "bin"
        self.calls = self.base / "calls.log"
        self.home.mkdir()
        self.bin.mkdir()
        self.calls.write_text("", encoding="utf-8")
        self._write_mocks()
        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "ARCHMIND_DATA_HOME": str(self.home / "ArchMind"),
                "ARCHMIND_TEST_SIMULATE": "1",
                "MOCK_CALLS": str(self.calls),
                "PATH": f"{self.bin}:/usr/bin:/bin",
            }
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _executable(self, name: str, content: str) -> None:
        target = self.bin / name
        target.write_text(content, encoding="utf-8")
        target.chmod(0o755)

    def _write_mocks(self) -> None:
        self._executable(
            "wineboot",
            """#!/usr/bin/env bash
set -eu
printf 'wineboot %s\n' "$*" >> "$MOCK_CALLS"
mkdir -p "$WINEPREFIX/drive_c"
printf 'WINE REGISTRY Version 2\n#arch=win64\n' > "$WINEPREFIX/system.reg"
printf 'WINE REGISTRY Version 2\n' > "$WINEPREFIX/user.reg"
: > "$WINEPREFIX/winetricks.log"
""",
        )
        self._executable(
            "wineserver",
            """#!/usr/bin/env bash
printf 'wineserver %s\n' "$*" >> "$MOCK_CALLS"
""",
        )
        self._executable(
            "wine",
            """#!/usr/bin/env bash
set -eu
printf 'wine %s\n' "$*" >> "$MOCK_CALLS"
if [[ "${1:-}" == reg && "${2:-}" == query && "${MOCK_VC14:-0}" == 1 ]]; then
  printf '    Installed    REG_DWORD    0x1\n'
  printf '    Version      REG_SZ       v14.44.35211.0\n'
  exit 0
fi
exit 1
""",
        )
        self._executable(
            "winetricks",
            """#!/usr/bin/env bash
set -eu
if [[ "${1:-}" == list-installed ]]; then
  [[ -f "$WINEPREFIX/winetricks.log" ]] && cat "$WINEPREFIX/winetricks.log"
  exit 0
fi
[[ "${1:-}" == -q && -n "${2:-}" ]] || exit 2
verb="$2"
printf 'winetricks %s\n' "$verb" >> "$MOCK_CALLS"
printf 'warning: new wow64 mode is experimental\n' >&2
if [[ "$verb" == "${MOCK_FAIL_VERB:-never}" ]]; then
  exit 55
fi
grep -Fxq -- "$verb" "$WINEPREFIX/winetricks.log" 2>/dev/null ||
  printf '%s\n' "$verb" >> "$WINEPREFIX/winetricks.log"
""",
        )
        self._executable(
            "pacman",
            """#!/usr/bin/env bash
printf 'pacman %s\n' "$*" >> "$MOCK_CALLS"
[[ "${1:-}" == -S ]]
""",
        )
        self._executable("sudo", "#!/usr/bin/env bash\nexec \"$@\"\n")
        self._executable("cabextract", "#!/usr/bin/env bash\nexit 0\n")
        self._executable("unzip", "#!/usr/bin/env bash\nexit 0\n")
        self._executable("7z", "#!/usr/bin/env bash\nexit 0\n")
        self._executable("vulkaninfo", "#!/usr/bin/env bash\nexit 0\n")

    def run_script(
        self, *arguments: str, extra_env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        environment = self.env.copy()
        if extra_env:
            environment.update(extra_env)
        return subprocess.run(
            ["bash", str(SCRIPT), *arguments],
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )

    def make_prefix(self, name: str = ".wine") -> Path:
        prefix = self.home / name
        (prefix / "drive_c").mkdir(parents=True)
        (prefix / "system.reg").write_text(
            "WINE REGISTRY Version 2\n#arch=win64\n", encoding="utf-8"
        )
        (prefix / "user.reg").write_text("WINE REGISTRY Version 2\n", encoding="utf-8")
        (prefix / "winetricks.log").write_text("corefonts\n", encoding="utf-8")
        return prefix

    def installed(self, prefix: Path) -> list[str]:
        return prefix.joinpath("winetricks.log").read_text(encoding="utf-8").splitlines()

    def test_plan_and_status_do_not_create_a_prefix(self) -> None:
        plan = self.run_script("--plan")
        status = self.run_script("--status")
        self.assertEqual((plan.returncode, status.returncode), (0, 0))
        self.assertIn(str(self.home / ".wine"), plan.stdout)
        self.assertIn("not initialized", status.stdout)
        self.assertFalse((self.home / ".wine").exists())
        self.assertFalse((self.home / "ArchMind").exists())

    def test_core_initializes_new_prefix_and_records_each_verb(self) -> None:
        result = self.run_script("--apply-core", "--yes")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        prefix = self.home / ".wine"
        expected = {
            "corefonts",
            "vcrun2005",
            "vcrun2008",
            "vcrun2010",
            "vcrun2012",
            "vcrun2013",
            "d3dcompiler_43",
            "d3dcompiler_47",
            "d3dx9",
            "d3dx10",
            "d3dx11_43",
            "d3dxof",
        }
        self.assertEqual(set(self.installed(prefix)), expected)
        self.assertEqual(
            list((self.home / "ArchMind/Installer-Backups/Wine").glob("*")), []
        )
        logs = list((self.home / "ArchMind/Logs/Wine-Compatibility").glob("*.log"))
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].stat().st_mode & 0o777, 0o600)
        receipts = list((self.home / "ArchMind/Config/Wine").glob("*.conf"))
        self.assertEqual(len(receipts), 1)
        receipt = receipts[0].read_text(encoding="utf-8")
        self.assertIn("prefix_relative=.wine", receipt)
        self.assertNotIn(str(self.home), receipt)

    def test_recommended_backs_up_once_and_skips_existing_vc14(self) -> None:
        prefix = self.make_prefix()
        result = self.run_script(
            "--apply-recommended", "--yes", extra_env={"MOCK_VC14": "1"}
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        installed = self.installed(prefix)
        self.assertNotIn("vcrun2022", installed)
        self.assertIn("xact", installed)
        self.assertIn("xact_x64", installed)
        self.assertIn("xinput", installed)
        backups = list((self.home / "ArchMind/Installer-Backups/Wine").glob("*"))
        self.assertEqual(len(backups), 1)
        self.assertTrue((backups[0] / ".archmind-wine-backup").is_file())
        self.assertEqual(
            (backups[0] / "winetricks.log").read_text(encoding="utf-8"), "corefonts\n"
        )

    def test_component_failure_is_reported_but_later_verbs_continue(self) -> None:
        self.make_prefix()
        result = self.run_script(
            "--apply-core", "--yes", extra_env={"MOCK_FAIL_VERB": "d3dx10"}
        )
        self.assertNotEqual(result.returncode, 0)
        calls = self.calls.read_text(encoding="utf-8")
        self.assertIn("winetricks d3dx10\n", calls)
        self.assertIn("winetricks d3dx11_43\n", calls)
        self.assertIn("1 component(s) failed", result.stderr)

    def test_inconsistent_vcrun2022_is_not_forced(self) -> None:
        prefix = self.make_prefix()
        with prefix.joinpath("winetricks.log").open("a", encoding="utf-8") as stream:
            stream.write("vcrun2022\n")
        result = self.run_script("--apply-modern-vc", "--yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("registry entries are incomplete", result.stdout)
        self.assertNotIn("winetricks vcrun2022", self.calls.read_text(encoding="utf-8"))

    def test_proton_and_nonprefix_content_are_refused(self) -> None:
        proton = self.home / ".local/share/Steam/steamapps/compatdata/123/pfx"
        result = self.run_script("--prefix", str(proton), "--plan")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Proton/Steam", result.stderr)

        unknown = self.home / "not-a-prefix"
        unknown.mkdir()
        (unknown / "important.txt").write_text("keep", encoding="utf-8")
        result = self.run_script("--prefix", str(unknown), "--apply-core", "--yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((unknown / "important.txt").read_text(encoding="utf-8"), "keep")
        self.assertFalse((unknown / "drive_c").exists())

        real_prefix = self.make_prefix("real-prefix")
        linked_prefix = self.home / "linked-prefix"
        linked_prefix.symlink_to(real_prefix, target_is_directory=True)
        result = self.run_script(
            "--prefix", str(linked_prefix), "--apply-core", "--yes"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symbolic-link", result.stderr)

    def test_dotnet48_never_accepts_noninteractive_yes(self) -> None:
        self.make_prefix()
        result = self.run_script("--apply-dotnet48", "--yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("dotnet48", self.calls.read_text(encoding="utf-8"))

    def test_base_install_is_explicit_and_uses_current_arch_package_names(self) -> None:
        result = self.run_script("--install-base", "--yes")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = self.calls.read_text(encoding="utf-8")
        self.assertIn("pacman -S --needed -- wine", calls)
        self.assertIn("winetricks", calls)
        self.assertIn("cabextract", calls)
        self.assertIn("unzip", calls)
        self.assertIn("7zip", calls)
        self.assertTrue((self.home / ".wine/drive_c").is_dir())

    @unittest.skipUnless(os.geteuid() == 0, "root refusal test")
    def test_real_mutation_refuses_root(self) -> None:
        environment = self.env.copy()
        environment.pop("ARCHMIND_TEST_SIMULATE", None)
        result = subprocess.run(
            ["bash", str(SCRIPT), "--apply-core", "--yes"],
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("normal user", result.stderr)
        self.assertFalse((self.home / ".wine").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
