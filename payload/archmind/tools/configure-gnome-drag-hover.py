#!/usr/bin/env python3
"""Manage the optional ArchMind GNOME Drag Hover patch safely."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile


UUID = "dash-to-dock@micxgx.gmail.com"
PATCH_FORMAT = 1
TESTED_DASH_VERSIONS = {105, 106}
DRAG_MARKER = "ARCHMIND_DRAG_HOVER_PATCH"
WINDOW_MARKER = "ARCHMIND_WINDOW_HOVER_PATCH"
INIT_ANCHOR = "        this.connect('destroy', this._onDestroy.bind(this));\n"
DESTROY_ANCHOR = "    _onDestroy() {\n        this.iconAnimator.destroy();\n"

INIT_PATCH = INIT_ANCHOR + f"""

        // {DRAG_MARKER}
        // Raise an application after an external file drag hovers over its icon.
        this._dragHoverPollId = 0;
        this._dragHoverTargetId = null;
        this._dragHoverSince = 0;
        this._dragHoverActivatedId = null;
        this._startExternalDragHover();
"""

METHODS_PATCH = f"""    // BEGIN {DRAG_MARKER}
    _startExternalDragHover() {{
        if (this._dragHoverPollId)
            return;

        this._dragHoverPollId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT,
            100,
            () => {{
                this._checkExternalDragHover();
                return GLib.SOURCE_CONTINUE;
            }}
        );
    }}

    _resetExternalDragHover() {{
        this._dragHoverTargetId = null;
        this._dragHoverSince = 0;
        this._dragHoverActivatedId = null;
    }}

    _trackExternalDragHover(targetId, activate) {{
        if (this._dragHoverTargetId !== targetId) {{
            this._dragHoverTargetId = targetId;
            this._dragHoverSince = GLib.get_monotonic_time();
            this._dragHoverActivatedId = null;
            return;
        }}

        if (this._dragHoverActivatedId === targetId)
            return;

        const elapsed =
            (GLib.get_monotonic_time() - this._dragHoverSince) / 1000;

        if (elapsed < 400)
            return;

        if (activate())
            this._dragHoverActivatedId = targetId;
    }}

    _checkExternalDragHover() {{
        const [x, y, mods] = global.get_pointer();

        if (!(mods & Clutter.ModifierType.BUTTON1_MASK)) {{
            this._resetExternalDragHover();
            return;
        }}

        let mimeTypes = [];
        try {{
            const selection = global.display.get_selection();
            // Meta.SelectionType.DND is 2. Keeping the numeric value avoids
            // adding an import to the host extension.
            mimeTypes = selection.get_mimetypes(2) ?? [];
        }} catch (error) {{
            this._resetExternalDragHover();
            return;
        }}

        const isFileDrag = mimeTypes.some(mime =>
            mime === 'text/uri-list' ||
            mime === 'x-special/gnome-icon-list' ||
            mime === 'application/octet-stream' ||
            mime === 'application/vnd.portal.filetransfer' ||
            mime.startsWith('image/')
        );

        if (!isFileDrag) {{
            this._resetExternalDragHover();
            return;
        }}

        for (const appIcon of this.getAppIcons()) {{
            if (!appIcon.app)
                continue;

            const [ok, localX, localY] =
                appIcon.transform_stage_point(x, y);

            if (!ok || localX < 0 || localY < 0 ||
                localX > appIcon.width || localY > appIcon.height)
                continue;

            const appId = appIcon.app.get_id();
            this._trackExternalDragHover(`app:${{appId}}`, () => {{
                if (appIcon.app.state !== Shell.AppState.RUNNING)
                    return false;
                const windows = appIcon.getInterestingWindows();
                if (windows.length === 0)
                    return false;
                Main.activateWindow(windows[0]);
                return true;
            }});
            return;
        }}

        // {WINDOW_MARKER}
        // Outside the dock, raise the topmost visible window below the pointer.
        const [dockOk, dockX, dockY] = this.transform_stage_point(x, y);
        if (dockOk && dockX >= 0 && dockY >= 0 &&
            dockX <= this.width && dockY <= this.height) {{
            this._resetExternalDragHover();
            return;
        }}

        const workspace = global.workspace_manager.get_active_workspace();
        let windows = global.display.list_all_windows().filter(window =>
            window &&
            window.showing_on_its_workspace() &&
            window.located_on_workspace(workspace) &&
            !window.is_skip_taskbar()
        );
        windows = global.display.sort_windows_by_stacking(windows);

        let targetWindow = null;
        for (let index = windows.length - 1; index >= 0; index--) {{
            const window = windows[index];
            const rect = window.get_frame_rect();
            if (x >= rect.x && x < rect.x + rect.width &&
                y >= rect.y && y < rect.y + rect.height) {{
                targetWindow = window;
                break;
            }}
        }}

        if (!targetWindow) {{
            this._resetExternalDragHover();
            return;
        }}

        const windowId = `window:${{targetWindow.get_id()}}`;
        this._trackExternalDragHover(windowId, () => {{
            Main.activateWindow(targetWindow);
            return true;
        }});
    }}
    // END {WINDOW_MARKER}

    _onDestroy() {{
        this.iconAnimator.destroy();

        if (this._dragHoverPollId) {{
            GLib.source_remove(this._dragHoverPollId);
            this._dragHoverPollId = 0;
        }}
"""


class PatchError(RuntimeError):
    """A safe, user-facing patch failure."""


def data_home() -> Path:
    return Path(os.environ.get("ARCHMIND_DATA_HOME", str(Path.home() / "ArchMind")))


def backup_root() -> Path:
    return data_home() / "Installer-Backups" / "GNOME-Drag-Hover"


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def refuse_root() -> None:
    if os.geteuid() == 0 and os.environ.get("ARCHMIND_TEST_SIMULATE") != "1":
        raise PatchError("Run this integration as your normal user, without sudo.")


def desktop_environment() -> str:
    return os.environ.get("XDG_CURRENT_DESKTOP", "Unknown")


def session_type() -> str:
    return os.environ.get("XDG_SESSION_TYPE", "Unknown").lower()


def gnome_shell_version() -> str:
    try:
        result = subprocess.run(
            ["gnome-shell", "--version"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return "Unavailable"
    return result.stdout.strip() or "Unavailable"


def extension_candidates() -> list[Path]:
    override = os.environ.get("ARCHMIND_DASH_TO_DOCK_DIR")
    if override:
        return [Path(override)]
    xdg_data = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    candidates = [xdg_data / "gnome-shell/extensions" / UUID]
    for item in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if item:
            candidates.append(Path(item) / "gnome-shell/extensions" / UUID)
    return candidates


def locate_extension(require_writable: bool = False) -> Path:
    existing = [candidate for candidate in extension_candidates() if candidate.is_dir()]
    if not existing:
        raise PatchError(f"Dash to Dock was not found ({UUID}).")
    extension = existing[0]
    dash = extension / "dash.js"
    if extension.is_symlink() or dash.is_symlink():
        raise PatchError("A symbolic-link Dash to Dock target was refused.")
    if not dash.is_file():
        raise PatchError(f"dash.js was not found in {extension}.")
    if require_writable and not os.access(dash, os.W_OK):
        if str(extension).startswith("/usr/"):
            raise PatchError(
                "Dash to Dock is system-managed and cannot be patched safely. "
                "Install a per-user copy before applying GNOME Drag Hover."
            )
        raise PatchError(f"dash.js is not writable by this user: {dash}")
    return extension


def extension_version(extension: Path) -> int | None:
    metadata = extension / "metadata.json"
    if metadata.is_symlink() or not metadata.is_file():
        return None
    try:
        value = json.loads(metadata.read_text(encoding="utf-8")).get("version")
        return int(value)
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return None


def marker_state(source: str) -> str:
    drag = source.count(DRAG_MARKER)
    window = source.count(WINDOW_MARKER)
    if drag == 2 and window == 2:
        return "installed"
    if drag == 0 and window == 0:
        return "absent"
    return "partial-or-modified"


def anchors_compatible(source: str) -> tuple[bool, str]:
    if source.count(INIT_ANCHOR) != 1:
        return False, "the Dash initialization anchor is missing or ambiguous"
    if source.count(DESTROY_ANCHOR) != 1:
        return False, "the Dash cleanup anchor is missing or ambiguous"
    if "getAppIcons()" not in source or "handleDragOver(" not in source:
        return False, "the expected Dash methods were not found"
    return True, "compatible anchors found"


def build_patched_source(source: str) -> str:
    if marker_state(source) != "absent":
        raise PatchError("The patch is already present or only partially present.")
    compatible, reason = anchors_compatible(source)
    if not compatible:
        raise PatchError(f"Unsupported dash.js structure: {reason}. No changes were made.")
    patched = source.replace(INIT_ANCHOR, INIT_PATCH, 1)
    patched = patched.replace(DESTROY_ANCHOR, METHODS_PATCH, 1)
    if marker_state(patched) != "installed":
        raise PatchError("Internal patch validation failed. No changes were made.")
    return patched


def atomic_write(path: Path, content: bytes) -> None:
    mode = stat.S_IMODE(path.stat().st_mode)
    temporary_name = ""
    try:
        with tempfile.NamedTemporaryFile(
            prefix=".dash.js.archmind-", dir=path.parent, delete=False
        ) as stream:
            temporary_name = stream.name
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary_name, mode)
        os.replace(temporary_name, path)
    finally:
        if temporary_name:
            Path(temporary_name).unlink(missing_ok=True)


def create_snapshot(
    dash: Path, version: int | None, original: bytes, patched: bytes
) -> Path:
    root = backup_root()
    if root.is_symlink():
        raise PatchError("The GNOME Drag Hover backup directory is a symbolic link.")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    stamp = datetime.now().astimezone().strftime("%Y%m%d-%H%M%S-%f")
    snapshot = root / f"apply-{stamp}-{os.getpid()}"
    snapshot.mkdir(mode=0o700)
    backup = snapshot / "dash.js.original"
    backup.write_bytes(original)
    shutil.copystat(dash, backup, follow_symlinks=False)
    metadata = {
        "format": PATCH_FORMAT,
        "created_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "extension_uuid": UUID,
        "extension_version": version,
        "target": str(dash),
        "original_sha256": sha256_bytes(original),
        "patched_sha256": sha256_bytes(patched),
    }
    metadata_path = snapshot / "metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    os.chmod(metadata_path, 0o600)
    return snapshot


def create_pre_restore_snapshot(dash: Path, current: bytes, source_snapshot: Path) -> Path:
    root = backup_root()
    if root.is_symlink():
        raise PatchError("The GNOME Drag Hover backup directory is a symbolic link.")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    stamp = datetime.now().astimezone().strftime("%Y%m%d-%H%M%S-%f")
    snapshot = root / f"restore-{stamp}-{os.getpid()}"
    snapshot.mkdir(mode=0o700)
    backup = snapshot / "dash.js.before-restore"
    backup.write_bytes(current)
    shutil.copystat(dash, backup, follow_symlinks=False)
    metadata = {
        "format": PATCH_FORMAT,
        "operation": "pre-restore",
        "created_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "extension_uuid": UUID,
        "target": str(dash),
        "current_sha256": sha256_bytes(current),
        "source_snapshot": source_snapshot.name,
    }
    metadata_path = snapshot / "metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    os.chmod(metadata_path, 0o600)
    return snapshot


def environment_check() -> None:
    desktop = desktop_environment().lower()
    session = session_type()
    simulated = os.environ.get("ARCHMIND_TEST_SIMULATE") == "1"
    if not simulated and "gnome" not in desktop:
        raise PatchError("GNOME was not detected in XDG_CURRENT_DESKTOP.")
    if not simulated and session != "wayland":
        raise PatchError("GNOME Drag Hover is validated only in a Wayland session.")


def install_patch(yes: bool = False) -> int:
    refuse_root()
    environment_check()
    extension = locate_extension(require_writable=True)
    dash = extension / "dash.js"
    source_bytes = dash.read_bytes()
    try:
        source = source_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PatchError("dash.js is not valid UTF-8; no changes were made.") from error
    state = marker_state(source)
    if state == "installed":
        print("GNOME Drag Hover is already installed; nothing changed.")
        return 0
    if state != "absent":
        raise PatchError("A partial or modified ArchMind patch was found. Restore manually first.")
    patched = build_patched_source(source).encode("utf-8")
    version = extension_version(extension)
    if version not in TESTED_DASH_VERSIONS and not yes:
        answer = input(
            f"Dash to Dock {version or 'unknown'} has compatible anchors but is not "
            "a validated version. Continue? [y/N]: "
        ).strip().lower()
        if answer not in {"y", "yes"}:
            print("Cancelled. No changes were made.")
            return 0
    snapshot = create_snapshot(dash, version, source_bytes, patched)
    try:
        atomic_write(dash, patched)
    except OSError as error:
        raise PatchError(f"Could not update dash.js; backup kept at {snapshot}: {error}") from error
    if sha256_file(dash) != sha256_bytes(patched):
        raise PatchError(f"Post-write verification failed. Restore snapshot: {snapshot}")
    print("GNOME Drag Hover installed successfully.")
    print(f"Dash to Dock version ... {version or 'Unknown'}")
    print(f"Safety snapshot ......... {snapshot}")
    print("Logout/login is required before testing it on Wayland.")
    return 0


def load_snapshots() -> list[tuple[Path, dict]]:
    root = backup_root()
    if not root.is_dir() or root.is_symlink():
        return []
    entries: list[tuple[Path, dict]] = []
    for snapshot in sorted(root.glob("apply-*"), reverse=True):
        metadata = snapshot / "metadata.json"
        backup = snapshot / "dash.js.original"
        if snapshot.is_symlink() or metadata.is_symlink() or backup.is_symlink():
            continue
        if not snapshot.is_dir() or not metadata.is_file() or not backup.is_file():
            continue
        try:
            values = json.loads(metadata.read_text(encoding="utf-8"))
            if values.get("format") != PATCH_FORMAT or values.get("extension_uuid") != UUID:
                continue
            if sha256_file(backup) != values.get("original_sha256"):
                continue
        except (OSError, ValueError, json.JSONDecodeError):
            continue
        entries.append((snapshot, values))
    return entries


def list_backups() -> int:
    entries = load_snapshots()
    print(f"GNOME Drag Hover snapshots: {len(entries)}")
    for index, (snapshot, metadata) in enumerate(entries, 1):
        print(
            f"{index:>2}) {snapshot.name} | Dash to Dock "
            f"{metadata.get('extension_version') or 'Unknown'}"
        )
    return 0


def compatible_snapshot(dash: Path) -> tuple[Path, dict] | None:
    current_hash = sha256_file(dash)
    for snapshot, metadata in load_snapshots():
        if metadata.get("target") == str(dash) and metadata.get("patched_sha256") == current_hash:
            return snapshot, metadata
    return None


def restore_snapshot(snapshot: Path, metadata: dict, dash: Path) -> int:
    backup = snapshot / "dash.js.original"
    current = dash.read_bytes()
    current_hash = sha256_bytes(current)
    if current_hash == metadata.get("original_sha256"):
        print("The original dash.js is already restored; nothing changed.")
        return 0
    if current_hash != metadata.get("patched_sha256"):
        raise PatchError(
            "dash.js changed after this snapshot. Refusing to overwrite a newer or "
            "manually modified file."
        )
    restore_safety = create_pre_restore_snapshot(dash, current, snapshot)
    atomic_write(dash, backup.read_bytes())
    if sha256_file(dash) != metadata.get("original_sha256"):
        raise PatchError("Restore verification failed.")
    print(f"Original dash.js restored from {snapshot}.")
    print(f"Pre-restore copy kept at {restore_safety}.")
    print("Logout/login is required before testing the restored extension on Wayland.")
    return 0


def remove_patch() -> int:
    refuse_root()
    extension = locate_extension(require_writable=True)
    dash = extension / "dash.js"
    source = dash.read_text(encoding="utf-8")
    state = marker_state(source)
    if state == "absent":
        print("GNOME Drag Hover is not installed; nothing changed.")
        return 0
    if state != "installed":
        raise PatchError("The patch is partial or modified; automatic removal was refused.")
    match = compatible_snapshot(dash)
    if not match:
        raise PatchError(
            "No exact safety snapshot matches the current patched dash.js. "
            "Automatic removal was refused."
        )
    return restore_snapshot(match[0], match[1], dash)


def restore_menu() -> int:
    refuse_root()
    extension = locate_extension(require_writable=True)
    dash = extension / "dash.js"
    entries = load_snapshots()
    if not entries:
        print("No valid GNOME Drag Hover snapshots were found.")
        return 0
    list_backups()
    answer = input("Snapshot number to restore [0 cancels]: ").strip()
    if not answer.isdigit() or int(answer) == 0:
        print("Cancelled. No changes were made.")
        return 0
    index = int(answer) - 1
    if index < 0 or index >= len(entries):
        raise PatchError("Invalid snapshot selection.")
    return restore_snapshot(entries[index][0], entries[index][1], dash)


def status() -> int:
    print("ArchMind GNOME Drag Hover")
    print(f"Desktop ................. {desktop_environment()}")
    print(f"Session ................. {session_type()}")
    print(f"GNOME Shell ............. {gnome_shell_version()}")
    try:
        extension = locate_extension()
    except PatchError as error:
        print(f"Dash to Dock ............ Not found ({error})")
        print("Patch ................... Not installed")
        return 0
    dash = extension / "dash.js"
    source = dash.read_text(encoding="utf-8")
    state = marker_state(source)
    compatible, reason = anchors_compatible(source) if state == "absent" else (False, "")
    version = extension_version(extension)
    snapshot_count = len(load_snapshots())
    labels = {
        "installed": "Installed",
        "absent": "Needs reapply after update" if snapshot_count else "Not installed",
        "partial-or-modified": "Partial or modified (manual review required)",
    }
    print(f"Dash to Dock ............ {version or 'Unknown'}")
    print(
        "Version support .......... "
        + (
            "Validated"
            if version in TESTED_DASH_VERSIONS
            else "Anchor-compatible only; confirmation required"
        )
    )
    print(f"Location ................ {extension}")
    print(f"Patch ................... {labels[state]}")
    if state == "absent":
        print(f"Compatibility ........... {'Ready' if compatible else 'Unsupported'} ({reason})")
    print(f"Safety snapshots ........ {snapshot_count}")
    if state == "installed":
        print("Activation .............. Logout/login required after file changes")
    return 0


def check_installed() -> int:
    try:
        extension = locate_extension()
        source = (extension / "dash.js").read_text(encoding="utf-8")
    except (PatchError, OSError, UnicodeError) as error:
        print(f"GNOME Drag Hover unavailable: {error}", file=sys.stderr)
        return 1
    state = marker_state(source)
    if state == "installed":
        print("GNOME Drag Hover is installed.")
        return 0
    if state == "absent" and load_snapshots():
        print("GNOME Drag Hover needs reapply after a Dash to Dock update.", file=sys.stderr)
    elif state == "absent":
        print("GNOME Drag Hover is not configured.", file=sys.stderr)
    else:
        print("GNOME Drag Hover is partial or modified.", file=sys.stderr)
    return 1


def menu() -> int:
    while True:
        print()
        status()
        print(
            "\n1) Install or reapply after a Dash to Dock update\n"
            "2) Verify status\n"
            "3) Remove safely\n"
            "4) List safety snapshots\n"
            "5) Restore a matching snapshot\n"
            "0) Back"
        )
        choice = input("\nChoice: ").strip()
        if choice == "1":
            install_patch()
        elif choice == "2":
            status()
        elif choice == "3":
            remove_patch()
        elif choice == "4":
            list_backups()
        elif choice == "5":
            restore_menu()
        elif choice == "0":
            return 0
        else:
            print("Invalid option.")
        input("\nPress Enter to continue...")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--menu", action="store_true")
    actions.add_argument("--status", action="store_true")
    actions.add_argument("--check", action="store_true")
    actions.add_argument("--install", action="store_true")
    actions.add_argument("--reapply", action="store_true")
    actions.add_argument("--remove", action="store_true")
    actions.add_argument("--list-backups", action="store_true")
    actions.add_argument("--restore", action="store_true")
    parser.add_argument(
        "--yes", action="store_true", help="accept a compatible but unvalidated extension version"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.install or args.reapply:
            return install_patch(args.yes)
        if args.remove:
            return remove_patch()
        if args.list_backups:
            return list_backups()
        if args.restore:
            return restore_menu()
        if args.check:
            return check_installed()
        if args.status:
            return status()
        return menu()
    except PatchError as error:
        print(f"GNOME Drag Hover: {error}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled. No changes were made.", file=sys.stderr)
        return 130
    except (OSError, UnicodeError) as error:
        print(f"GNOME Drag Hover: file operation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
