#!/usr/bin/env python3
"""Real nested AFI/curses handoff: no package or network operations."""
import fcntl
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import termios
import time

CORE = Path(__file__).resolve().parents[1] / "payload/archmind"
with tempfile.TemporaryDirectory(prefix="archmind-handoff-") as home:
    master, slave = pty.openpty()
    original = termios.tcgetattr(slave)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 0, 0))
    command = r'''
source "$1/core/afi/init.zsh"
afi_init || exit 1
printf '\e[?1049h'
afi_dispatch_action monitor-live
print -r -- AFI_RETURN_OK
afi_reset_terminal_state
printf '\e[?1049l'
'''
    process = subprocess.Popen(["zsh", "-dfc", command, "test", str(CORE)], stdin=slave,
        stdout=slave, stderr=slave, env={**os.environ, "HOME": home, "TERM": "xterm-256color",
        "ARCHMIND_DATA_HOME": home + "/ArchMind"}, start_new_session=True)
    output = bytearray()
    sent_quit = sent_enter = False
    deadline = time.monotonic() + 10
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.05)[0]:
                output.extend(os.read(master, 65536))
            if not sent_quit and b"ARCHMIND MONITOR" in output:
                os.write(master, b"q")
                sent_quit = True
            if not sent_enter and b"Press Enter to return" in output:
                os.write(master, b"\r")
                sent_enter = True
            if process.poll() is not None:
                break
        process.wait(timeout=1)
        assert process.returncode == 0, output.decode(errors="replace")[-2000:]
        assert sent_quit and sent_enter
        assert b"AFI_RETURN_OK" in output
        assert b"Traceback" not in output and b"command not found" not in output
        assert output.rfind(b"\x1b[?1049h") < output.index(b"AFI_RETURN_OK")
        assert output.count(b"\x1b[?1049h") >= 3
        assert termios.tcgetattr(slave) == original
        print("[OK] Real AFI -> Live Monitor -> AFI handoff; terminal restored.")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
