"""Shared private state for ArchMind maintenance tools."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import stat
from typing import Iterable

from runtime_files import private_directory, safe_text


TASK_FILE = "pending-tasks.json"
PROFILE_FILE = "operating-profile.json"
PACKAGE_BASELINE_FILE = "package-baseline.json"
VALID_SEVERITIES = {"info", "warning", "critical"}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def state_directory(create: bool = True):
    return private_directory(("State", "Maintenance"), create=create)


def _read_json(name: str, default, parts=("State", "Maintenance")):
    directory, directory_fd = private_directory(parts, create=True)
    try:
        try:
            file_fd = os.open(
                name,
                os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                dir_fd=directory_fd,
            )
        except FileNotFoundError:
            return default
        try:
            info = os.fstat(file_fd)
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != os.getuid()
                or info.st_size > 2 * 1024 * 1024
            ):
                raise ValueError(f"Unsafe maintenance state file: {name}")
            with os.fdopen(file_fd, "r", encoding="utf-8", errors="strict", closefd=False) as stream:
                return json.load(stream)
        finally:
            os.close(file_fd)
    finally:
        os.close(directory_fd)


def _write_json(name: str, value, parts=("State", "Maintenance")) -> Path:
    directory, directory_fd = private_directory(parts, create=True)
    temporary = f".{name}.{os.getpid()}.tmp"
    try:
        file_fd = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
            dir_fd=directory_fd,
        )
        try:
            payload = (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
            offset = 0
            while offset < len(payload):
                offset += os.write(file_fd, payload[offset:])
            os.fsync(file_fd)
        finally:
            os.close(file_fd)
        os.replace(temporary, name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
        os.fsync(directory_fd)
    except BaseException:
        try:
            os.unlink(temporary, dir_fd=directory_fd)
        except FileNotFoundError:
            pass
        raise
    finally:
        os.close(directory_fd)
    return directory / name


def load_tasks() -> list[dict]:
    raw = _read_json(TASK_FILE, {"format": 1, "tasks": []})
    if not isinstance(raw, dict) or raw.get("format") != 1:
        raise ValueError("Unsupported pending-task state format")
    tasks = raw.get("tasks", [])
    if not isinstance(tasks, list):
        raise ValueError("Invalid pending-task list")
    valid = []
    for task in tasks:
        if not isinstance(task, dict):
            continue
        task_id = safe_text(str(task.get("id", "")))[:80]
        if not task_id or not all(c.isalnum() or c in "-_." for c in task_id):
            continue
        valid.append(
            {
                "id": task_id,
                "title": safe_text(str(task.get("title", task_id)))[:160],
                "detail": safe_text(str(task.get("detail", "")))[:800],
                "severity": task.get("severity") if task.get("severity") in VALID_SEVERITIES else "warning",
                "source": safe_text(str(task.get("source", "ArchMind")))[:100],
                "created_at": safe_text(str(task.get("created_at", "")))[:64],
                "updated_at": safe_text(str(task.get("updated_at", "")))[:64],
                "resolved": bool(task.get("resolved", False)),
            }
        )
    return valid


def save_tasks(tasks: Iterable[dict]) -> Path:
    return _write_json(TASK_FILE, {"format": 1, "tasks": list(tasks)})


def upsert_task(task_id: str, title: str, detail: str, severity="warning", source="ArchMind") -> Path:
    if severity not in VALID_SEVERITIES:
        raise ValueError("Invalid task severity")
    if not task_id or not all(c.isalnum() or c in "-_." for c in task_id):
        raise ValueError("Invalid task identifier")
    now = utc_now()
    tasks = load_tasks()
    for task in tasks:
        if task["id"] == task_id:
            task.update(
                title=safe_text(title)[:160],
                detail=safe_text(detail)[:800],
                severity=severity,
                source=safe_text(source)[:100],
                updated_at=now,
                resolved=False,
            )
            return save_tasks(tasks)
    tasks.append(
        {
            "id": task_id,
            "title": safe_text(title)[:160],
            "detail": safe_text(detail)[:800],
            "severity": severity,
            "source": safe_text(source)[:100],
            "created_at": now,
            "updated_at": now,
            "resolved": False,
        }
    )
    return save_tasks(tasks)


def resolve_task(task_id: str) -> bool:
    tasks = load_tasks()
    changed = False
    for task in tasks:
        if task["id"] == task_id and not task["resolved"]:
            task["resolved"] = True
            task["updated_at"] = utc_now()
            changed = True
    if changed:
        save_tasks(tasks)
    return changed


def clear_resolved() -> int:
    tasks = load_tasks()
    remaining = [task for task in tasks if not task["resolved"]]
    removed = len(tasks) - len(remaining)
    if removed:
        save_tasks(remaining)
    return removed


def load_profile() -> dict:
    raw = _read_json(PROFILE_FILE, {"format": 1, "profile": "normal"}, ("Config", "Maintenance"))
    if not isinstance(raw, dict) or raw.get("format") != 1:
        return {"format": 1, "profile": "normal"}
    return raw


def save_profile(profile: str, monitor_interval: float, notes: list[str]) -> Path:
    return _write_json(
        PROFILE_FILE,
        {
            "format": 1,
            "profile": profile,
            "monitor_interval": monitor_interval,
            "notes": [safe_text(note)[:240] for note in notes],
            "updated_at": utc_now(),
        },
        ("Config", "Maintenance"),
    )


def load_package_baseline() -> dict[str, str]:
    raw = _read_json(PACKAGE_BASELINE_FILE, {"format": 1, "packages": {}})
    if not isinstance(raw, dict) or raw.get("format") != 1 or not isinstance(raw.get("packages"), dict):
        raise ValueError("Invalid package-baseline state")
    packages = {}
    for name, version in raw["packages"].items():
        name = safe_text(str(name))[:200]
        version = safe_text(str(version))[:300]
        if name and all(c.isalnum() or c in "-_.+@" for c in name):
            packages[name] = version
    return packages


def save_package_baseline(packages: dict[str, str]) -> Path:
    cleaned = {
        safe_text(name)[:200]: safe_text(version)[:300]
        for name, version in packages.items()
        if name and all(c.isalnum() or c in "-_.+@" for c in name)
    }
    return _write_json(PACKAGE_BASELINE_FILE, {"format": 1, "packages": cleaned})


def human_size(size: int) -> str:
    value = float(max(0, size))
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024 or unit == "TiB":
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024
    return f"{value:.1f} TiB"
