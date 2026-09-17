#!/usr/bin/env python3
"""Isolated regression tests; optional root-only simulation on disposable copies."""
import hashlib
import os
import shutil
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1]


class SafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="archmind-safety-")
        self.root = Path(self.temp.name)
        self.home = self.root / "home com espaços"
        self.home.mkdir()
        self.package = self.root / "ArchMind-1.5.18"
        shutil.copytree(SOURCE, self.package)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:/usr/bin:/bin", TERM="xterm-256color")
        self.env.pop("ZDOTDIR", None)
        self.simulated = os.geteuid() == 0
        if self.simulated and os.environ.get("ARCHMIND_TEST_SIMULATE") != "1":
            self.temp.cleanup()
            self.skipTest("Run as a normal user, or set ARCHMIND_TEST_SIMULATE=1 for disposable-copy simulation")
        self.helper = self.package / "payload/archmind/tools/organize-home-zsh.sh"
        self.installer = self.package / "install.sh"
        if self.simulated:
            # Never change the deliverable: only fixtures under TemporaryDirectory.
            self.installer.write_text(self.installer.read_text().replace(
                "if (( ! dry_run && ! check_only && EUID == 0 )); then", "if (( 0 )); then"))
            self.helper.write_text(self.helper.read_text().replace("(( EUID != 0 ))", "(( 1 ))"))
            self.manifest()

    def tearDown(self):
        self.temp.cleanup()

    def manifest(self):
        lines = []
        for path in sorted((self.package / "payload").rglob("*")):
            if path.is_file():
                lines.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(self.package)}\n")
        (self.package / "PAYLOAD.sha256").write_text("".join(lines))

    def run_cmd(self, *args, code=0):
        result = subprocess.run([str(a) for a in args], env=self.env, cwd=self.home,
                                text=True, input="", stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT,
                                timeout=40)
        if code is not None:
            self.assertEqual(result.returncode, code, result.stdout)
        return result

    def write(self, relative, text):
        target = self.home / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def duplicate(self, name, subdir="theme"):
        target = self.home / name
        shutil.copy2(self.package / f"payload/archmind/{subdir}/{name}", target)
        return target

    def mock(self, name, text):
        target = self.bin / name
        target.write_text("#!/bin/bash\n" + text)
        target.chmod(0o755)

    def test_scan_moves_nothing(self):
        source = self.duplicate("startup.zsh")
        before = source.read_bytes()
        result = self.run_cmd("bash", self.helper, "--check")
        self.assertIn("[CANDIDATE] startup.zsh", result.stdout)
        self.assertEqual(source.read_bytes(), before)
        self.assertFalse((self.home / "ArchMind").exists())
        self.run_cmd("bash", self.helper, "--offer")
        self.assertTrue(source.exists())  # no interactive approval

    def test_monitor_launcher_install_and_rollback(self):
        self.run_cmd("bash", self.installer, "--no-progress")
        launcher = self.home / ".local/bin/archmind-monitor"
        self.assertTrue(launcher.is_symlink())
        self.assertIn("ArchMind Monitor 0.1.0", self.run_cmd(launcher, "--version").stdout)
        previous = os.readlink(launcher)
        original = self.installer.read_text()
        self.installer.write_text(original.replace(
            "    write_install_record\n", "    false # simulated late failure\n    write_install_record\n"))
        self.run_cmd("bash", self.installer, "--no-progress", code=1)
        self.assertEqual(os.readlink(launcher), previous)
        self.run_cmd(launcher, "--version")

    def test_move_restore_conflicts_and_custom_files(self):
        source = self.duplicate("startup.zsh")
        before = source.read_bytes()
        colors = self.duplicate("colors.zsh")
        self.write(".zshrc", 'source "$HOME/colors.zsh"\n')
        custom = self.write("aliases.zsh", "# meu arquivo personalizado\n")
        unrelated = self.write("pessoal.zsh", "# fora da lista\n")
        (self.home / "git.zsh").symlink_to(custom)
        result = self.run_cmd("bash", self.helper, "--apply")
        self.assertIn("[OK]", result.stdout)
        self.assertFalse(source.exists())
        self.assertTrue(colors.exists())
        self.assertTrue(custom.exists())
        self.assertTrue(unrelated.exists())
        self.assertTrue((self.home / "git.zsh").is_symlink())
        batch = next((self.home / "ArchMind/Config/Zsh/Imported-Home").iterdir())
        backup = next((self.home / "ArchMind/Installer-Backups").iterdir())
        self.assertEqual((batch / "startup.zsh").read_bytes(), before)
        self.assertEqual((backup / "startup.zsh").read_bytes(), before)
        self.run_cmd("bash", self.helper, "--apply")  # idempotent
        source.write_text("# não sobrescrever\n")
        self.run_cmd("bash", self.helper, "--restore", batch, code=1)
        self.assertEqual(source.read_text(), "# não sobrescrever\n")
        source.unlink()  # only our fixture, not a user file
        self.run_cmd("bash", self.helper, "--restore", batch)
        self.assertEqual(source.read_bytes(), before)

    def test_dynamic_source_and_link_destination_are_preserved(self):
        source = self.duplicate("startup.zsh")
        rc = self.write(".zshrc", 'source "$HOME"/*.zsh\n')
        self.run_cmd("bash", self.helper, "--apply")
        self.assertTrue(source.exists())
        rc.write_text("# sem source\n")
        outside = self.root / "outside"
        outside.mkdir()
        (self.home / "ArchMind").symlink_to(outside)
        self.run_cmd("bash", self.helper, "--apply", code=1)
        self.assertTrue(source.exists())
        self.assertEqual(list(outside.iterdir()), [])

    def test_move_failure_restores_originals(self):
        self.duplicate("colors.zsh")
        self.duplicate("startup.zsh")
        self.mock("mv", 'case "$*" in *startup.zsh*) exit 29;; esac\nexec /usr/bin/mv "$@"\n')
        self.run_cmd("bash", self.helper, "--apply", code=29)
        self.assertTrue((self.home / "colors.zsh").exists())
        self.assertTrue((self.home / "startup.zsh").exists())

    def test_clean_and_repeated_install_with_direct_import(self):
        aliases = self.write(".zsh_aliases", "alias teste='true'\n")
        p10k = self.write(".p10k.zsh", "# p10k personalizado\n")
        rc = self.write(".zshrc", 'source "$HOME/.zsh_aliases"\nsource "$HOME/.p10k.zsh"\n')
        self.run_cmd("bash", self.installer)
        self.assertTrue(aliases.is_symlink())
        self.assertTrue(p10k.is_symlink())
        self.assertEqual(aliases.read_text(), "alias teste='true'\n")
        self.run_cmd("bash", self.installer)
        self.assertEqual(rc.read_text().count('source "$HOME/.zsh_aliases"'), 1)
        self.run_cmd(self.home / ".local/bin/archmind-console", "--version")
        desktop = (self.home / ".local/share/applications/archmind-execute-terminal.desktop").read_text()
        self.assertIn(f'Exec="{self.home}/ArchMind/System/Core/tools/execute-in-terminal.sh" %f', desktop)
        self.run_cmd("zsh", "-n", rc)

    def test_conflicting_aliases_are_not_replaced(self):
        old = self.write(".zsh_aliases", "# home personalizada\n")
        new = self.write("ArchMind/Config/Zsh/aliases.zsh", "# central personalizada\n")
        rc = self.write(".zshrc", 'source "$HOME/.zsh_aliases"\n')
        self.run_cmd("bash", self.installer)
        self.assertFalse(old.is_symlink())
        self.assertEqual(old.read_text(), "# home personalizada\n")
        self.assertEqual(new.read_text(), "# central personalizada\n")
        self.assertNotIn("Config/Zsh/aliases.zsh", rc.read_text())

    def test_late_install_failure_rolls_back_shell_and_config(self):
        self.run_cmd("bash", self.installer)
        rc = self.write(".zshrc", "# shell original\n")
        aliases = self.write("ArchMind/Config/Zsh/aliases.zsh", "# central original\n")
        conf = self.write("ArchMind/Config/archmind.conf", "# config original\n")
        desktop = self.write(".local/share/applications/archmind-execute-terminal.desktop", "# desktop original\n")
        before = {p: p.read_bytes() for p in (rc, aliases, conf, desktop)}
        original_core = (self.home / ".config/archmind").readlink()
        self.mock("chmod", 'case "$*" in *archmind-execute-terminal.desktop*) exit 23;; esac\nexec /usr/bin/chmod "$@"\n')
        self.run_cmd("bash", self.installer, code=23)
        for path, contents in before.items():
            self.assertEqual(path.read_bytes(), contents, str(path))
        self.assertEqual((self.home / ".config/archmind").readlink(), original_core)
        self.run_cmd(self.home / ".local/bin/archmind-console", "--version")

    def test_read_only_and_symlink_preflight(self):
        target = self.write(".zshrc", "# somente leitura\n")
        if not self.simulated:
            target.chmod(0o400)
            self.run_cmd("bash", self.installer, code=1)
            self.assertFalse((self.home / "ArchMind/System/Core").exists())
        target.chmod(0o600)
        target.unlink()
        outside = self.root / "external-rc"
        outside.write_text("# não alterar\n")
        target.symlink_to(outside)
        self.run_cmd("bash", self.installer, code=1)
        self.assertEqual(outside.read_text(), "# não alterar\n")

    def test_desktop_exec_escaping(self):
        text = self.installer.read_text()
        body = text.split("desktop_quote() {", 1)[1].split("\n}", 1)[0]
        code = 'desktop_quote() {' + body + '\n}\ndesktop_quote "$1"'
        value = '/home/usuário com "aspas"/$valor/`texto`/100%/barra\\arquivo'
        result = self.run_cmd("bash", "-c", code, "bash", value)
        # GKeyFile string escapes, then Desktop Entry argument quoting, then %%.
        escaped = result.stdout
        decoded = []
        index = 0
        while index < len(escaped):
            if escaped[index] == "\\":
                index += 1
                decoded.append({"\\": "\\", "n": "\n", "r": "\r", "t": "\t", "s": " "}[escaped[index]])
            else:
                decoded.append(escaped[index])
            index += 1
        argv = shlex.split("".join(decoded))
        # shlex keeps escaped $ and ` inside quotes; Desktop Entry removes them.
        actual = argv[0].replace("\\$", "$" ).replace("\\`", "`").replace("%%", "%")
        self.assertEqual(actual, value)

    def test_original_installer_still_refuses_root(self):
        if not self.simulated:
            self.skipTest("Root-refusal test requires root")
        result = self.run_cmd("bash", SOURCE / "install.sh", code=1)
        self.assertIn("not as root", result.stdout)
        self.assertFalse((self.home / "ArchMind").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
