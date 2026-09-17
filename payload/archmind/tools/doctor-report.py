#!/usr/bin/env python3
"""Save completed Doctor results; viewing never runs diagnosis or repair."""
import argparse
from datetime import datetime, timezone
import os
import re
import secrets
import sys
from pathlib import Path

from runtime_files import private_directory, read_private_file, safe_text

PATTERN = re.compile(r"report-\d{8}T\d{12}Z-[0-9a-f]{12}\.txt\Z")


def save_report(kind, version, body):
    if not body.strip() or len(body.encode("utf-8")) > 1024 * 1024:
        raise ValueError("Diagnosis is empty or exceeds the report size limit")
    directory, fd = private_directory(("Logs", "Doctor"), create=True)
    stamp = datetime.now(timezone.utc)
    token = secrets.token_hex(6)
    name = f"report-{stamp:%Y%m%dT%H%M%S%fZ}-{token}.txt"
    temporary = f".pending-{token}"
    created = False
    try:
        report_fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
        created = True
        with os.fdopen(report_fd, "w", encoding="utf-8") as stream:
            stream.write(f"ArchMind Doctor / {safe_text(version)}\n")
            stream.write(f"Diagnosis: {safe_text(kind)}\nRecorded: {stamp.isoformat()}\n")
            stream.write("Read-only checks. No repair or package upgrade was performed.\n")
            stream.write("Review system details before sharing this report.\n\n")
            stream.write(safe_text(body).rstrip() + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        # Publish a complete inode without overwriting any earlier report.
        os.link(temporary, name, src_dir_fd=fd, dst_dir_fd=fd, follow_symlinks=False)
        os.unlink(temporary, dir_fd=fd)
        created = False
        return directory / name
    finally:
        if created:
            os.unlink(temporary, dir_fd=fd)
        os.close(fd)


def latest_report():
    try:
        directory, fd = private_directory(("Logs", "Doctor"))
    except FileNotFoundError:
        return "No saved report. Run Quick Diagnosis or Full Diagnosis first."
    try:
        names = sorted((name for name in os.listdir(fd) if PATTERN.fullmatch(name)), reverse=True)
        if not names:
            return "No saved report. Run Quick Diagnosis or Full Diagnosis first."
        # Refuse a corrupted or redirected latest report instead of silently
        # showing an older successful report as the newest result.
        return f"Report: {directory / names[0]}\n\n" + read_private_file(fd, names[0])
    finally:
        os.close(fd)


def copy_reports(source_fd, target_fd):
    count = 0
    for name in sorted(os.listdir(source_fd)):
        if not PATTERN.fullmatch(name):
            continue
        text = read_private_file(source_fd, name)
        temporary = ".pending-" + secrets.token_hex(6)
        file_fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                          0o600, dir_fd=target_fd)
        try:
            with os.fdopen(file_fd, "w", encoding="utf-8") as stream:
                stream.write(text)
                stream.flush()
                os.fsync(stream.fileno())
            try:
                os.link(temporary, name, src_dir_fd=target_fd, dst_dir_fd=target_fd, follow_symlinks=False)
                count += 1
            except FileExistsError:
                # Restore is additive; preserve all pre-existing report files.
                pass
        finally:
            os.unlink(temporary, dir_fd=target_fd)
    return count


def transfer_reports(path, importing=False):
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    if importing:
        source_fd = os.open(path, flags)
        try:
            _, target_fd = private_directory(("Logs", "Doctor"), create=True)
            try:
                return copy_reports(source_fd, target_fd)
            finally:
                os.close(target_fd)
        finally:
            os.close(source_fd)
    try:
        _, source_fd = private_directory(("Logs", "Doctor"))
    except FileNotFoundError:
        return 0
    try:
        Path(path).mkdir(mode=0o700, exist_ok=True)
        target_fd = os.open(path, flags)
        try:
            os.fchmod(target_fd, 0o700)
            return copy_reports(source_fd, target_fd)
        finally:
            os.close(target_fd)
    finally:
        os.close(source_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--save", choices=("Quick", "Full", "Pacman", "Audio"))
    group.add_argument("--export", dest="export_dir")
    group.add_argument("--import", dest="import_dir")
    parser.add_argument("--version", default="1.5.18")
    args = parser.parse_args()
    try:
        if args.save:
            result = save_report(args.save, args.version, sys.stdin.read(1024 * 1024 + 1))
            print(f"Saved report: {result}")
        elif args.export_dir or args.import_dir:
            count = transfer_reports(args.import_dir or args.export_dir, bool(args.import_dir))
            print(f"Doctor reports copied: {count}; existing files preserved.")
        else:
            print(latest_report())
        return 0
    except (OSError, ValueError) as error:
        print(f"Report unavailable: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
