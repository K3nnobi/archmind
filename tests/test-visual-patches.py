#!/usr/bin/env python3
"""Isolated tests for NVIDIA Vibrance and Plymouth boot integrations."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NVIDIA = ROOT / "payload/archmind/tools/configure-nvibrant.sh"
PLYMOUTH = ROOT / "payload/archmind/patches/plymouth/plymouth-patch.sh"


class VisualPatchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="archmind-visual-test-")
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.system = self.base / "system"
        self.bin = self.base / "bin"
        self.log = self.base / "calls.log"
        self.home.mkdir()
        self.bin.mkdir()
        self.log.write_text("", encoding="utf-8")
        self._create_system()
        self._create_mocks()
        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.home / ".config"),
                "ARCHMIND_DATA_HOME": str(self.home / "ArchMind"),
                "ARCHMIND_PLYMOUTH_ROOT": str(self.system),
                "ARCHMIND_MACHINE_ID_FILE": str(self.system / "etc/machine-id"),
                "ARCHMIND_TEST_SIMULATE": "1",
                "ARCHMIND_TEST_NVIDIA": "1",
                "ARCHMIND_TEST_LOG": str(self.log),
                "PATH": f"{self.bin}:/usr/bin:/bin",
            }
        )
        self.originals = {
            path: path.read_bytes()
            for path in (
                self.system / "etc/plymouth/plymouthd.conf",
                self.system / "etc/mkinitcpio.conf",
                self.system / "etc/default/grub",
                self.system / "etc/grub.d/10_linux",
            )
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _write_executable(self, name: str, text: str) -> None:
        path = self.bin / name
        path.write_text(text, encoding="utf-8")
        path.chmod(0o755)

    def _create_system(self) -> None:
        for path in (
            self.system / "etc/plymouth",
            self.system / "etc/default",
            self.system / "etc/grub.d",
            self.system / "boot/grub",
        ):
            path.mkdir(parents=True)
        (self.system / "etc/machine-id").write_text("abc123\n", encoding="utf-8")
        (self.system / "etc/plymouth/plymouthd.conf").write_text(
            "[Daemon]\nTheme=fade-in\nShowDelay=0\n", encoding="utf-8"
        )
        (self.system / "etc/mkinitcpio.conf").write_text(
            "MODULES=(nvme)\n"
            "HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)\n",
            encoding="utf-8",
        )
        (self.system / "etc/default/grub").write_text(
            'GRUB_TIMEOUT=3\nGRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 nvidia_drm.modeset=1"\n',
            encoding="utf-8",
        )
        script = self.system / "etc/grub.d/10_linux"
        script.write_text(
            "#!/usr/bin/env bash\n"
            'message="$(gettext_printf "Loading Linux %s ..." ${version})"\n'
            "echo '$(echo \"$message\" | grub_quote)'\n"
            "linux /vmlinuz-linux-lts\n"
            'message="$(gettext_printf "Loading initial ramdisk ...")"\n'
            "echo '$(echo \"$message\" | grub_quote)'\n"
            "initrd /initramfs-linux-lts.img\n",
            encoding="utf-8",
        )
        script.chmod(0o755)
        (self.system / "boot/grub/grub.cfg").write_text("old\n", encoding="utf-8")

    def _create_mocks(self) -> None:
        self._write_executable(
            "mkinitcpio",
            """#!/usr/bin/env bash
printf 'mkinitcpio %s\n' "$*" >> "$ARCHMIND_TEST_LOG"
[[ "${ARCHMIND_TEST_REBUILD_FAIL:-0}" != 1 ]]
""",
        )
        self._write_executable(
            "grub-mkconfig",
            """#!/usr/bin/env bash
printf 'grub-mkconfig %s\n' "$*" >> "$ARCHMIND_TEST_LOG"
while (($#)); do
  if [[ "$1" == -o ]]; then printf 'generated\n' > "$2"; break; fi
  shift
done
""",
        )
        self._write_executable(
            "pacman",
            """#!/usr/bin/env bash
[[ "${1:-}" == -Q ]] && exit 0
exit 2
""",
        )
        self._write_executable(
            "plymouth-set-default-theme",
            """#!/usr/bin/env bash
[[ "${1:-}" == -l ]] && printf 'spinner\n'
""",
        )
        self._write_executable(
            "nvibrant",
            """#!/usr/bin/env bash
printf 'nvibrant %s\n' "$*" >> "$ARCHMIND_TEST_LOG"
""",
        )
        self._write_executable(
            "systemctl",
            """#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$ARCHMIND_TEST_LOG"
if [[ "${1:-}" == --user && "${2:-}" == is-enabled ]]; then exit 0; fi
exit 0
""",
        )

    def run_script(self, script: Path, *args: str, **env: str) -> subprocess.CompletedProcess[str]:
        command_env = self.env.copy()
        command_env.update(env)
        return subprocess.run(
            ["bash", str(script), *args],
            env=command_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )

    def test_plymouth_apply_is_idempotent_and_remove_is_exact(self) -> None:
        first = self.run_script(PLYMOUTH, "--apply")
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
        second = self.run_script(PLYMOUTH, "--reapply")
        self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
        check = self.run_script(PLYMOUTH, "--check")
        self.assertEqual(check.returncode, 0, check.stderr + check.stdout)

        mkinit = (self.system / "etc/mkinitcpio.conf").read_text(encoding="utf-8")
        grub_default = (self.system / "etc/default/grub").read_text(encoding="utf-8")
        grub_script = (self.system / "etc/grub.d/10_linux").read_text(encoding="utf-8")
        self.assertEqual(mkinit.count("plymouth"), 1)
        self.assertIn("udev plymouth autodetect", mkinit)
        self.assertIn("nvidia_drm.modeset=1 quiet splash", grub_default)
        self.assertEqual(grub_script.count("ARCHMIND_PLYMOUTH_HIDE_"), 2)
        snapshots = list((self.home / "ArchMind/Installer-Backups/Plymouth").glob("apply-*"))
        self.assertEqual(len(snapshots), 1)

        removed = self.run_script(PLYMOUTH, "--remove")
        self.assertEqual(removed.returncode, 0, removed.stderr + removed.stdout)
        for path, original in self.originals.items():
            self.assertEqual(path.read_bytes(), original, path)
        self.assertFalse((self.home / "ArchMind/Config/Patches/Plymouth/state.conf").exists())

    def test_plymouth_unsupported_grub_layout_changes_nothing(self) -> None:
        script = self.system / "etc/grub.d/10_linux"
        script.write_text("#!/bin/sh\nlinux /vmlinuz\n", encoding="utf-8")
        before = {path: path.read_bytes() for path in self.originals}
        result = self.run_script(PLYMOUTH, "--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported", result.stderr)
        for path, content in before.items():
            self.assertEqual(path.read_bytes(), content)

    def test_existing_plymouth_hook_returns_to_its_original_position(self) -> None:
        config = self.system / "etc/mkinitcpio.conf"
        original = (
            "MODULES=(nvme)\n"
            "HOOKS=(base udev autodetect microcode plymouth modconf kms block filesystems fsck)\n"
        )
        config.write_text(original, encoding="utf-8")
        self.assertEqual(self.run_script(PLYMOUTH, "--apply").returncode, 0)
        self.assertIn("udev plymouth autodetect", config.read_text(encoding="utf-8"))
        self.assertEqual(self.run_script(PLYMOUTH, "--remove").returncode, 0)
        self.assertEqual(config.read_text(encoding="utf-8"), original)

    def test_plymouth_rebuild_failure_rolls_back(self) -> None:
        result = self.run_script(PLYMOUTH, "--apply", ARCHMIND_TEST_REBUILD_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        for path, original in self.originals.items():
            self.assertEqual(path.read_bytes(), original, path)
        self.assertFalse((self.home / "ArchMind/Config/Patches/Plymouth/state.conf").exists())

    def test_plymouth_adopts_already_commented_grub_messages(self) -> None:
        script = self.system / "etc/grub.d/10_linux"
        original = script.read_text(encoding="utf-8").replace(
            "echo '$(echo \"$message\" | grub_quote)'",
            "# echo '$(echo \"$message\" | grub_quote)'",
        )
        script.write_text(original, encoding="utf-8")
        applied = self.run_script(PLYMOUTH, "--apply")
        self.assertEqual(applied.returncode, 0, applied.stderr + applied.stdout)
        managed = script.read_text(encoding="utf-8")
        self.assertEqual(managed.count("ARCHMIND_PLYMOUTH_PREHIDDEN_"), 2)
        self.assertEqual(self.run_script(PLYMOUTH, "--remove").returncode, 0)
        self.assertEqual(script.read_text(encoding="utf-8"), original)

    def test_plymouth_adopts_already_removed_grub_messages(self) -> None:
        script = self.system / "etc/grub.d/10_linux"
        original = script.read_text(encoding="utf-8").replace(
            "echo '$(echo \"$message\" | grub_quote)'\n",
            "",
        )
        script.write_text(original, encoding="utf-8")
        applied = self.run_script(PLYMOUTH, "--apply")
        self.assertEqual(applied.returncode, 0, applied.stderr + applied.stdout)
        self.assertEqual(script.read_text(encoding="utf-8").count("__MISSING__"), 2)
        self.assertEqual(self.run_script(PLYMOUTH, "--remove").returncode, 0)
        self.assertEqual(script.read_text(encoding="utf-8"), original)

    def test_nvibrant_preserves_previous_service_and_validates_value(self) -> None:
        unit = self.home / ".config/systemd/user/nvibrant.service"
        unit.parent.mkdir(parents=True)
        old = "[Service]\nType=oneshot\nExecStart=/usr/bin/nvibrant 400\n"
        unit.write_text(old, encoding="utf-8")

        invalid = self.run_script(NVIDIA, "--set", "2048")
        self.assertNotEqual(invalid.returncode, 0)
        self.assertEqual(unit.read_text(encoding="utf-8"), old)

        applied = self.run_script(NVIDIA, "--set", "700")
        self.assertEqual(applied.returncode, 0, applied.stderr + applied.stdout)
        self.assertIn("ExecStartPre=/usr/bin/sleep 5", unit.read_text(encoding="utf-8"))
        self.assertIn("ExecStart=/usr/bin/nvibrant 700", unit.read_text(encoding="utf-8"))
        self.assertEqual(
            (self.home / "ArchMind/Config/NVIDIA/vibrance.conf").read_text(encoding="utf-8"),
            "NVIBRANT_VALUE=700\n",
        )
        backup_count = len(list((self.home / "ArchMind/Installer-Backups/NVIDIA-Vibrance").glob("nvibrant.service-before-*")))
        self.assertEqual(self.run_script(NVIDIA, "--apply").returncode, 0)
        self.assertEqual(
            len(list((self.home / "ArchMind/Installer-Backups/NVIDIA-Vibrance").glob("nvibrant.service-before-*"))),
            backup_count,
        )
        self.assertEqual(self.run_script(NVIDIA, "--reapply").returncode, 0)

        removed = self.run_script(NVIDIA, "--remove")
        self.assertEqual(removed.returncode, 0, removed.stderr + removed.stdout)
        self.assertEqual(unit.read_text(encoding="utf-8"), old)
        calls = self.log.read_text(encoding="utf-8")
        self.assertIn("systemctl --user enable --now nvibrant.service", calls)
        self.assertIn("nvibrant 700", calls)

    def test_nvibrant_falls_back_to_bin_package(self) -> None:
        (self.bin / "nvibrant").unlink()
        self._write_executable(
            "yay",
            """#!/usr/bin/env bash
if [[ "${1:-}" == -Si ]]; then
  [[ "${*: -1}" == nvibrant-bin ]]
  exit
fi
if [[ "${1:-}" == -S && "${*: -1}" == nvibrant-bin ]]; then
  printf '#!/usr/bin/env bash\nexit 0\n' > "$ARCHMIND_TEST_MOCK_BIN/nvibrant"
  chmod 755 "$ARCHMIND_TEST_MOCK_BIN/nvibrant"
  exit 0
fi
exit 2
""",
        )
        result = self.run_script(
            NVIDIA,
            "--apply",
            ARCHMIND_TEST_MOCK_BIN=str(self.bin),
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertTrue((self.bin / "nvibrant").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
