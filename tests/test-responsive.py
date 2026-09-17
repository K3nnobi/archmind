#!/usr/bin/env python3
"""PTY-level checks for AFI resize handling and terminal boundaries."""

from __future__ import annotations

import fcntl
import os
import pty
import select
import struct
import tempfile
import termios
import time
import unicodedata
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
CONSOLE = PACKAGE_ROOT / "payload/archmind/console/main.zsh"
ARCHMIND_ROOT = PACKAGE_ROOT / "payload/archmind"
CLEAR = b"\x1b[2J\x1b[H"


def set_size(fd: int, rows: int, columns: int) -> None:
    fcntl.ioctl(
        fd,
        termios.TIOCSWINSZ,
        struct.pack("HHHH", rows, columns, 0, 0),
    )


def collect(fd: int, duration: float) -> bytes:
    deadline = time.monotonic() + duration
    output = bytearray()
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if not ready:
            continue
        try:
            output.extend(os.read(fd, 65536))
        except OSError:
            break
    return bytes(output)


def collect_frame(
    fd: int, markers: bytes | tuple[bytes, ...], timeout: float = 10.0
) -> bytes:
    required = (markers,) if isinstance(markers, bytes) else markers
    deadline = time.monotonic() + timeout
    output = bytearray()
    last_data = 0.0
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.05)
        now = time.monotonic()
        if ready:
            try:
                output.extend(os.read(fd, 65536))
                last_data = now
            except OSError:
                break
            continue
        if any(marker in output for marker in required) and now - last_data >= 0.25:
            break
    return bytes(output)


def spawn_console(rows: int, columns: int, test_home: str) -> tuple[int, int]:
    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update(
            TERM="xterm-256color",
            HOME=test_home,
            AFI_INPUT_POLL_INTERVAL="0.05",
        )
        set_size(0, rows, columns)
        os.execvp("zsh", ["zsh", str(CONSOLE)])
    set_size(fd, rows, columns)
    return pid, fd


def spawn_overlay(
    overlay: str, rows: int, columns: int, test_home: str
) -> tuple[int, int]:
    scripts = {
        "viewer": (
            'afi_viewer "Responsive Viewer" '
            '"Line 1" "Line 2" "Line 3" "Line 4" "Line 5" '
            '"Line 6" "Line 7" "Line 8" "Line 9" "Line 10"'
        ),
        "dialog": (
            'afi_confirm_dialog "Responsive Dialog" '
            '"Resize-safe confirmation" 54'
        ),
    }
    command = scripts[overlay]
    code = (
        'source "$ARCHMIND_TEST_ROOT/core/afi/init.zsh"; '
        "afi_init || exit 1; "
        "typeset -gi resize_requested=0; "
        "trap 'resize_requested=1' WINCH; "
        "printf '\\e[?1049h'; afi_disable_wrap; "
        f"{command}; result_code=$?; "
        "afi_reset_terminal_state; printf '\\e[?1049l'; exit $result_code"
    )

    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update(
            TERM="xterm-256color",
            HOME=test_home,
            ARCHMIND_TEST_ROOT=str(ARCHMIND_ROOT),
            AFI_INPUT_POLL_INTERVAL="0.05",
        )
        set_size(0, rows, columns)
        os.execvp("zsh", ["zsh", "-c", code])
    set_size(fd, rows, columns)
    return pid, fd


def character_width(character: str) -> int:
    if unicodedata.combining(character):
        return 0
    return 2 if unicodedata.east_asian_width(character) in {"W", "F"} else 1


def assert_within_terminal(data: bytes, rows: int, columns: int) -> None:
    """Reject cursor moves or printable output beyond the current PTY."""
    text = data.decode("utf-8", "ignore")
    row = 0
    column = 0
    index = 0

    while index < len(text):
        character = text[index]
        if character == "\x1b" and index + 1 < len(text):
            if text[index + 1] == "[":
                end = index + 2
                while end < len(text) and not ("@" <= text[end] <= "~"):
                    end += 1
                if end >= len(text):
                    break
                parameters = text[index + 2 : end]
                command = text[end]
                if command in {"H", "f"} and not parameters.startswith("?"):
                    values = parameters.split(";") if parameters else []
                    target_row = int(values[0] or "1") if values else 1
                    target_column = (
                        int(values[1] or "1") if len(values) > 1 else 1
                    )
                    row = target_row - 1
                    column = target_column - 1
                    assert 0 <= row < rows, (row, rows, parameters)
                    assert 0 <= column < columns, (column, columns, parameters)
                index = end + 1
                continue
            index += 2
            continue

        if character == "\r":
            column = 0
        elif character == "\n":
            row += 1
        elif ord(character) >= 32:
            width = character_width(character)
            assert column + width <= columns, (column, width, columns, character)
            column += width
        index += 1


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="archmind-responsive-") as test_home:
        # 44x173 reproduces the large GNOME Terminal geometry previously used
        # to validate the ArchMind borders.
        pid, fd = spawn_console(44, 173, test_home)
        segments: list[tuple[int, int, bytes]] = []

        # Capability discovery may take a few seconds on slower CI hosts.
        initial = collect_frame(fd, b"INFORMATION")
        segments.append((44, 173, initial))
        assert b"v2.1 Responsive" in initial
        assert b"SYSTEM STATUS" in initial
        assert b"INFORMATION" in initial

        cases = [
            (24, 80, b"v2.1 Responsive"),
            (10, 55, b"More options"),
            (6, 30, b"Enlarge the window"),
            (35, 110, b"SYSTEM STATUS"),
        ]
        for rows, columns, marker in cases:
            set_size(fd, rows, columns)
            segment = collect_frame(fd, marker)
            segments.append((rows, columns, segment))
            assert CLEAR in segment, (rows, columns, "frame was not redrawn")
            assert marker in segment, (rows, columns, marker)

        for rows, columns, segment in segments:
            assert_within_terminal(segment, rows, columns)

        os.write(fd, b"q")
        dialog = collect_frame(fd, b"EXIT ARCHMIND")
        assert b"EXIT ARCHMIND" in dialog
        os.write(fd, b"\r")
        collect(fd, 0.5)

        waited_pid, status = os.waitpid(pid, 0)
        assert waited_pid == pid
        assert os.waitstatus_to_exitcode(status) == 0

        render_log = Path(test_home) / "ArchMind/Logs/render-errors.log"
        assert not render_log.read_text(encoding="utf-8"), "render log is not empty"
        render_log.unlink()

        # Viewer and confirmation overlays own their redraw loops and must also
        # survive resize events without waiting for an ordinary key.
        for overlay, marker, compact_marker in [
            ("viewer", b"RESPONSIVE VIEWER", b"Responsive Viewer"),
            ("dialog", b"RESPONSIVE DIALOG", b"Responsive Dialog"),
        ]:
            pid, fd = spawn_overlay(overlay, 25, 90, test_home)
            first = collect_frame(fd, marker)
            assert marker in first
            assert_within_terminal(first, 25, 90)

            for rows, columns in [(7, 35), (5, 25), (28, 100)]:
                set_size(fd, rows, columns)
                segment = collect_frame(fd, (marker, compact_marker))
                assert CLEAR in segment, (overlay, rows, columns)
                assert marker in segment or compact_marker in segment, (
                    overlay,
                    rows,
                    columns,
                    segment[-200:],
                )
                assert_within_terminal(segment, rows, columns)

            os.write(fd, b"\r")
            collect(fd, 0.3)
            _, status = os.waitpid(pid, 0)
            assert os.waitstatus_to_exitcode(status) == 0

    print(
        "[OK] AFI responsive: full, standard, compact, minimum-size, "
        "viewer and dialogs."
    )


if __name__ == "__main__":
    main()
