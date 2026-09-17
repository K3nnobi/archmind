#!/usr/bin/env python3
"""Optional Firefox / ChatGPT Color Emoji Fix for the default Firefox profile."""

from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime

BEGIN = "/* ARCHMIND-CHATGPT-EMOJI-BEGIN */"
END = "/* ARCHMIND-CHATGPT-EMOJI-END */"
BLOCK = f'''{BEGIN}
@-moz-document domain("chatgpt.com"), domain("chat.openai.com") {{
    div[data-message-author-role="assistant"],
    div[data-message-author-role="assistant"] *,
    div[data-message-author-role="user"],
    div[data-message-author-role="user"] * {{
        font-family: "OpenAI Sans", "Noto Color Emoji", "Adwaita Sans", sans-serif !important;
    }}
}}
{END}'''
PREF = 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
PREF_RE = re.compile(
    r"""^\s*user_pref\s*\(\s*["']toolkit\.legacyUserProfileCustomizations\.stylesheets["']\s*,.*?\)\s*;\s*$"""
)


class PatchError(Exception):
    pass


def firefox_root() -> Path:
    return Path.home() / ".mozilla" / "firefox"


def data_root() -> Path:
    return Path.home() / "ArchMind"


def safe_path(path: Path, root: Path) -> None:
    """Refuse symlinks and profile paths that escape the Firefox directory."""
    if not path.is_relative_to(root):
        raise PatchError(f"Firefox profile is outside its profile directory: {path}")
    if ".." in path.relative_to(root).parts:
        raise PatchError(f"Firefox profile contains a parent traversal: {path}")
    if root.parent.is_symlink():
        raise PatchError(f"Symbolic-link path refused: {root.parent}")
    current = root
    if current.is_symlink():
        raise PatchError(f"Symbolic-link path refused: {current}")
    for part in path.relative_to(root).parts:
        current = current / part
        if current.is_symlink():
            raise PatchError(f"Symbolic-link path refused: {current}")
    if path.exists() and not (path.is_file() or path.is_dir()):
        raise PatchError(f"Special file refused: {path}")


def safe_data(path: Path) -> None:
    root = data_root()
    if root.is_symlink():
        raise PatchError(f"Symbolic-link path refused: {root}")
    safe_path(path, root)


def profiles() -> list[tuple[configparser.SectionProxy, Path]]:
    root = firefox_root()
    ini = root / "profiles.ini"
    safe_path(ini, root)
    if not ini.is_file():
        raise PatchError(f"Firefox profiles.ini was not found: {ini}")
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.read(ini, encoding="utf-8")
    entries = []
    for section in config.sections():
        if not section.startswith("Profile"):
            continue
        entry = config[section]
        raw = entry.get("Path", "").strip()
        if not raw:
            continue
        path = (root / raw if entry.get("IsRelative", "1") == "1" else Path(raw)).absolute()
        safe_path(path, root)
        if path.is_dir():
            entries.append((entry, path))
    if not entries:
        raise PatchError("No usable Firefox profile was found.")
    return entries


def select_profile() -> Path:
    entries = profiles()
    defaults = [path for entry, path in entries if entry.get("Default", "0") == "1"]
    if defaults:
        return next((path for path in defaults if "default-release" in path.name), defaults[0])
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.read(firefox_root() / "profiles.ini", encoding="utf-8")
    for section in config.sections():
        if not section.startswith("Install"):
            continue
        default = config[section].get("Default", "")
        for _, path in entries:
            if default in (path.name, str(path.relative_to(firefox_root()))):
                return path
    return next((path for _, path in entries if "default-release" in path.name), entries[0][1])


def locations(profile: Path) -> tuple[Path, Path, Path, Path]:
    key = hashlib.sha256(str(profile).encode()).hexdigest()[:20]
    state = data_root() / "Config" / "Firefox-ChatGPT-Emoji" / (key + ".json")
    backups = data_root() / "Backups" / "Safety" / "firefox-chatgpt-emoji" / key
    css = profile / "chrome" / "userContent.css"
    user_js = profile / "user.js"
    for path in (css, user_js):
        safe_path(path, firefox_root())
        if path.exists() and not path.is_file():
            raise PatchError(f"Regular file required: {path}")
    for path in (state, backups):
        safe_data(path)
    return css, user_js, state, backups


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8") if path.exists() else ""
    except UnicodeError as error:
        raise PatchError(f"Non-UTF-8 Firefox customization: {path}") from error


def css_change(content: str) -> tuple[str, str | None]:
    if content.count(BEGIN) != content.count(END) or content.count(BEGIN) > 1:
        raise PatchError("Incomplete or repeated ArchMind CSS markers; review userContent.css manually.")
    original = None
    if BEGIN in content:
        start, end = content.index(BEGIN), content.index(END) + len(END)
        if start >= end:
            raise PatchError("ArchMind CSS markers are in the wrong order.")
        original = content[start:end]
        return content[:start] + BLOCK + content[end:], original
    separator = "" if not content or content.endswith("\n") else "\n"
    return content + separator + BLOCK + "\n", original


def pref_change(content: str) -> tuple[str, list[str]]:
    lines = content.splitlines(keepends=True)
    originals = [line for line in lines if PREF_RE.fullmatch(line.rstrip("\r\n"))]
    if originals == [PREF + "\n"]:
        return content, originals
    filtered = [line for line in lines if line not in originals]
    prefix = "" if not filtered or filtered[-1].endswith("\n") else "\n"
    return "".join(filtered) + prefix + PREF + "\n", originals


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=".archmind-emoji-", dir=path.parent)
    try:
        if path.exists():
            os.fchmod(fd, path.stat().st_mode & 0o777)
        else:
            os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
            stream.write(content)
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def check_environment() -> None:
    if os.geteuid() == 0 and os.environ.get("ARCHMIND_TEST_SIMULATE") != "1":
        raise PatchError("Run as your normal user, without sudo.")
    if not shutil.which("firefox"):
        raise PatchError("Firefox was not found.")


def ensure_font() -> None:
    if not shutil.which("pacman"):
        raise PatchError("Pacman is required on Arch Linux.")
    if subprocess.run(["pacman", "-Q", "noto-fonts-emoji"], check=False, stdout=subprocess.DEVNULL).returncode:
        if not shutil.which("sudo"):
            raise PatchError("sudo is needed to install noto-fonts-emoji.")
        subprocess.run(["sudo", "pacman", "-S", "--needed", "noto-fonts-emoji"], check=True)
    if not shutil.which("fc-cache") or not shutil.which("fc-match"):
        raise PatchError("fontconfig tools fc-cache and fc-match are required.")
    subprocess.run(["fc-cache", "-f"], check=True)
    match = subprocess.check_output(["fc-match", "-f", "%{family}\n", "Noto Color Emoji"], text=True).strip()
    if "Noto Color Emoji" not in match:
        raise PatchError(f"Noto Color Emoji was not found by fontconfig (matched: {match}).")


def firefox_running() -> bool:
    return bool(shutil.which("pgrep") and any(
        subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", name], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False).returncode == 0
        for name in ("firefox", "firefox-bin")
    ))


def state_read(path: Path, profile: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        state = json.loads(read_text(path))
    except ValueError as error:
        raise PatchError(f"Invalid ArchMind state file: {path}") from error
    if state.get("profile") != str(profile):
        raise PatchError("Firefox profile and ArchMind state do not match.")
    return state


def apply() -> int:
    check_environment()
    profile = select_profile()
    css, user_js, state_path, backup_root = locations(profile)
    old_css, old_js = read_text(css), read_text(user_js)
    new_css, old_block = css_change(old_css)
    new_js, original_pref = pref_change(old_js)
    existing = state_read(state_path, profile)
    ensure_font()
    if old_css == new_css and old_js == new_js:
        print(f"Already configured: {profile}")
    else:
        # Preserve first-install ownership for accurate rollback on repeated runs.
        state = existing or {
            "profile": str(profile), "css_original_block": old_block,
            "pref_original_lines": original_pref, "css_created": not css.exists(),
            "user_js_created": not user_js.exists(), "pref_changed": old_js != new_js,
            "css_original_had_trailing_newline": old_css.endswith("\n"),
        }
        if existing and old_js != new_js and not existing["pref_changed"]:
            state["pref_changed"] = True
            state["pref_original_lines"] = original_pref
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup = backup_root / stamp
        safe_data(backup)
        backup.mkdir(parents=True, exist_ok=False)
        for source in (css, user_js):
            if source.exists() and ((source == css and old_css != new_css) or
                                    (source == user_js and old_js != new_js)):
                shutil.copy2(source, backup / (source.name + ".bak"))
        try:
            if old_css != new_css:
                write_text(css, new_css)
            if old_js != new_js:
                write_text(user_js, new_js)
            state_path.parent.mkdir(parents=True, exist_ok=True)
            write_text(state_path, json.dumps(state, indent=2) + "\n")
        except (OSError, ValueError):
            # Restore exact pre-operation contents if a later write fails.
            if old_css != new_css:
                if css.exists() and old_css:
                    write_text(css, old_css)
                elif css.exists():
                    css.unlink()
            if old_js != new_js:
                if user_js.exists() and old_js:
                    write_text(user_js, old_js)
                elif user_js.exists():
                    user_js.unlink()
            raise
        print(f"ChatGPT color emoji fix installed in {profile}")
        print(f"Safety copy: {backup}")
    print("Noto Color Emoji installed; Firefox custom styles enabled.")
    print("Firefox is currently running. Completely restart it to activate the fix." if firefox_running()
          else "Start Firefox to activate the fix.")
    return 0


def remove() -> int:
    profile = select_profile()
    css, user_js, state_path, _ = locations(profile)
    state = state_read(state_path, profile)
    if not state:
        print("No ArchMind-managed Firefox emoji patch was found.")
        return 0
    old_css, old_js = read_text(css), read_text(user_js)
    if old_css.count(BEGIN) != 1 or old_css.count(END) != 1:
        raise PatchError("Managed CSS block was changed or removed; no files were modified.")
    start, end = old_css.index(BEGIN), old_css.index(END) + len(END)
    if old_css[start:end] != BLOCK:
        raise PatchError("Managed CSS block was edited; no files were modified.")
    replacement = state.get("css_original_block")
    if replacement is None:
        prefix, suffix = old_css[:start], old_css[end:]
        if suffix.startswith("\n"):
            suffix = suffix[1:]
        if not state.get("css_original_had_trailing_newline", True) and prefix.endswith("\n"):
            prefix = prefix[:-1]
        new_css = prefix + suffix
    else:
        new_css = old_css[:start] + replacement + old_css[end:]
    if state.get("pref_changed"):
        lines = old_js.splitlines(keepends=True)
        pref_lines = [line for line in lines if PREF_RE.fullmatch(line.rstrip("\r\n"))]
        if pref_lines != [PREF + "\n"]:
            raise PatchError("Firefox preference was changed; no files were modified.")
        new_js = "".join(line for line in lines if line not in pref_lines) + "".join(
            state.get("pref_original_lines", [])
        )
    else:
        new_js = old_js
    if new_css != old_css:
        if state.get("css_created") and not new_css.strip():
            css.unlink()
        else:
            write_text(css, new_css)
    if new_js != old_js:
        if state.get("user_js_created") and not new_js.strip():
            user_js.unlink()
        else:
            write_text(user_js, new_js)
    state_path.unlink()
    print("ArchMind ChatGPT emoji rules removed; other Firefox customizations preserved.")
    print("Completely restart Firefox to apply the change.")
    return 0


def status() -> int:
    profile = select_profile()
    css, user_js, state_path, _ = locations(profile)
    print(f"Firefox profile ............ {profile}")
    matched_font = subprocess.run(["fc-match", "-f", "%{family}", "Noto Color Emoji"],
                                  check=False, capture_output=True, text=True).stdout if shutil.which("fc-match") else ""
    print(f"Noto Color Emoji ........... {'installed' if 'Noto Color Emoji' in matched_font else 'missing'}")
    print(f"Firefox custom styles ...... {'enabled' if PREF in read_text(user_js) else 'not configured'}")
    print(f"ChatGPT emoji CSS .......... {'configured' if BLOCK in read_text(css) else 'not configured'}")
    print(f"ArchMind rollback state .... {'available' if state_read(state_path, profile) else 'unavailable'}")
    return 0


def menu() -> int:
    print("\nFirefox / ChatGPT Color Emoji Fix\n")
    print("1) Apply or update")
    print("2) Status")
    print("3) Remove ArchMind changes")
    print("0) Back")
    choice = input("\nChoice: ").strip()
    if choice in ("1", "3"):
        answer = input("Proceed with the selected action? [y/N]: ").strip().lower()
        if answer not in ("y", "yes"):
            print("Cancelled. No changes were made.")
            return 0
    return {"1": apply, "2": status, "3": remove}.get(choice, lambda: 0)()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    for action in ("menu", "apply", "status", "remove"):
        group.add_argument("--" + action, dest="action", action="store_const", const=action)
    args = parser.parse_args()
    try:
        return {"menu": menu, "apply": apply, "status": status, "remove": remove}[args.action or "menu"]()
    except (PatchError, OSError, subprocess.CalledProcessError, configparser.Error) as error:
        print(f"Firefox / ChatGPT emoji patch: {error}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
