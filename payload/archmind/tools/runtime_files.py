"""Private ArchMind runtime files. No symlink traversal outside the user's home."""
import os
from pathlib import Path
import stat


def private_directory(parts, create=False):
    home = Path.home().resolve()
    base = Path(os.environ.get("ARCHMIND_DATA_HOME", str(home / "ArchMind")))
    if not base.is_absolute() or ".." in base.parts:
        raise ValueError("ArchMind data path must be absolute and inside Home")
    relative = base.relative_to(home)
    names = (*relative.parts, *parts)
    if not relative.parts or any(n in ("", ".", "..") or "/" in n for n in names):
        raise ValueError("Unsafe ArchMind data directory")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    fd = os.open(home, flags)
    try:
        for name in names:
            try:
                new = os.open(name, flags, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    raise
                os.mkdir(name, 0o700, dir_fd=fd)
                new = os.open(name, flags, dir_fd=fd)
            os.close(fd)
            fd = new
            info = os.fstat(fd)
            if info.st_uid != os.getuid() or info.st_mode & 0o022:
                raise PermissionError("ArchMind runtime directory is not private to this user")
        if create:
            os.fchmod(fd, 0o700)
        return base.joinpath(*parts), fd
    except BaseException:
        os.close(fd)
        raise


def safe_text(text):
    return "".join(c for c in text if c in "\n\t" or c.isprintable())


def read_private_file(fd, name, limit=1024 * 1024):
    file_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    try:
        info = os.fstat(file_fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > limit:
            raise ValueError("Report is not a readable, regular user-owned file")
        with os.fdopen(file_fd, "r", encoding="utf-8", errors="replace", closefd=False) as stream:
            return safe_text(stream.read(limit))
    finally:
        os.close(file_fd)
