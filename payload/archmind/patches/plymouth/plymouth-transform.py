#!/usr/bin/env python3
"""Pure text transformations for the ArchMind Plymouth patch.

This helper never writes system files. The privileged shell wrapper stages and
validates every result before installing it.
"""

from __future__ import annotations

import argparse
import re
import shlex
from pathlib import Path


THEME_RE = re.compile(r"^[A-Za-z0-9_.+-]+$")
HOOKS_RE = re.compile(r"^(?P<prefix>\s*HOOKS\s*=\s*\()(?P<body>[^)]*)(?P<suffix>\).*)$")
CMDLINE_RE = re.compile(
    r"^(?P<prefix>\s*GRUB_CMDLINE_LINUX_DEFAULT\s*=\s*)(?P<quote>['\"])(?P<body>.*)(?P=quote)(?P<suffix>\s*(?:#.*)?)$"
)
HIDE_PREFIX = {
    "linux": "# ARCHMIND_PLYMOUTH_HIDE_LINUX: ",
    "initrd": "# ARCHMIND_PLYMOUTH_HIDE_INITRD: ",
}
PREHIDDEN_PREFIX = {
    "linux": "# ARCHMIND_PLYMOUTH_PREHIDDEN_LINUX: ",
    "initrd": "# ARCHMIND_PLYMOUTH_PREHIDDEN_INITRD: ",
}
ECHO_MESSAGE_RE = re.compile(
    r"^echo\s+['\"]?\$\(echo\s+\"\$message\"\s*\|\s*grub_quote\)['\"]?$"
)


class TransformError(RuntimeError):
    pass


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def split_lines(content: str) -> list[str]:
    return content.splitlines(keepends=True)


def theme_value(content: str) -> str | None:
    inside = False
    found: list[str] = []
    for raw in content.splitlines():
        stripped = raw.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            inside = stripped == "[Daemon]"
            continue
        if inside and re.match(r"^\s*Theme\s*=", raw):
            found.append(raw.split("=", 1)[1].strip())
    if len(found) > 1:
        raise TransformError("multiple active Theme entries exist in [Daemon]")
    if found and not THEME_RE.fullmatch(found[0]):
        raise TransformError("the existing Plymouth theme name is unsafe")
    return found[0] if found else None


def set_theme(content: str, value: str | None) -> str:
    if value is not None and not THEME_RE.fullmatch(value):
        raise TransformError("invalid Plymouth theme name")
    lines = split_lines(content)
    result: list[str] = []
    inside = False
    daemon_seen = False
    theme_written = False

    for raw in lines:
        stripped = raw.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if inside and value is not None and not theme_written:
                result.append(f"Theme={value}\n")
                theme_written = True
            inside = stripped == "[Daemon]"
            daemon_seen = daemon_seen or inside
            result.append(raw)
            continue
        if inside and re.match(r"^\s*Theme\s*=", raw):
            if value is not None and not theme_written:
                newline = "\n" if raw.endswith("\n") else ""
                result.append(f"Theme={value}{newline}")
                theme_written = True
            continue
        result.append(raw)

    if not daemon_seen:
        if result and not result[-1].endswith("\n"):
            result[-1] += "\n"
        if result and result[-1].strip():
            result.append("\n")
        result.append("[Daemon]\n")
        if value is not None:
            result.append(f"Theme={value}\n")
    elif inside and value is not None and not theme_written:
        if result and not result[-1].endswith("\n"):
            result[-1] += "\n"
        result.append(f"Theme={value}\n")
    return "".join(result)


def transform_hooks(
    content: str, previous_index: int | None = None
) -> tuple[str, bool, int]:
    lines = split_lines(content)
    matches = [(index, HOOKS_RE.match(line.rstrip("\n"))) for index, line in enumerate(lines)]
    matches = [(index, match) for index, match in matches if match]
    if len(matches) != 1:
        raise TransformError("expected exactly one active HOOKS=(...) line")
    index, match = matches[0]
    assert match is not None
    try:
        hooks = shlex.split(match.group("body"), posix=True)
    except ValueError as error:
        raise TransformError(f"could not parse mkinitcpio HOOKS: {error}") from error
    if any(not re.fullmatch(r"[A-Za-z0-9_+.-]+", hook) for hook in hooks):
        raise TransformError("mkinitcpio HOOKS contains an unsupported token")

    if hooks.count("plymouth") > 1:
        raise TransformError("mkinitcpio HOOKS contains duplicate plymouth entries")
    had_plymouth = "plymouth" in hooks
    old_index = hooks.index("plymouth") if had_plymouth else -1
    hooks = [hook for hook in hooks if hook != "plymouth"]
    if previous_index is None:
        if "udev" not in hooks:
            raise TransformError("the supported udev hook is missing; systemd hooks are not changed automatically")
        hooks.insert(hooks.index("udev") + 1, "plymouth")
    elif previous_index >= 0:
        hooks.insert(min(previous_index, len(hooks)), "plymouth")
    replacement = match.group("prefix") + " ".join(hooks) + match.group("suffix")
    if lines[index].endswith("\n"):
        replacement += "\n"
    lines[index] = replacement
    return "".join(lines), not had_plymouth, old_index


def cmdline_tokens(body: str) -> list[str]:
    try:
        return shlex.split(body, posix=True)
    except ValueError as error:
        raise TransformError(f"could not parse GRUB_CMDLINE_LINUX_DEFAULT: {error}") from error


def transform_cmdline(
    content: str, *, remove_quiet: bool = False, remove_splash: bool = False
) -> tuple[str, bool, bool]:
    lines = split_lines(content)
    matches = [(index, CMDLINE_RE.match(line.rstrip("\n"))) for index, line in enumerate(lines)]
    matches = [(index, match) for index, match in matches if match]
    if len(matches) != 1:
        raise TransformError("expected exactly one GRUB_CMDLINE_LINUX_DEFAULT line")
    index, match = matches[0]
    assert match is not None
    body = match.group("body")
    tokens = cmdline_tokens(body)
    if tokens.count("quiet") > 1 or tokens.count("splash") > 1:
        raise TransformError("GRUB_CMDLINE_LINUX_DEFAULT contains duplicate quiet or splash tokens")
    had_quiet = "quiet" in tokens
    had_splash = "splash" in tokens

    if remove_quiet or remove_splash:
        if remove_quiet:
            body = re.sub(r"(?<!\S)quiet(?:\s+|$)", "", body).rstrip()
        if remove_splash:
            body = re.sub(r"(?<!\S)splash(?:\s+|$)", "", body).rstrip()
    else:
        additions = []
        if not had_quiet:
            additions.append("quiet")
        if not had_splash:
            additions.append("splash")
        if additions:
            body = body.rstrip()
            body = f"{body} {' '.join(additions)}".strip()

    replacement = (
        match.group("prefix")
        + match.group("quote")
        + body
        + match.group("quote")
        + match.group("suffix")
    )
    if lines[index].endswith("\n"):
        replacement += "\n"
    lines[index] = replacement
    return "".join(lines), not had_quiet, not had_splash


def hide_grub_messages(content: str) -> tuple[str, dict[str, bool]]:
    lines = split_lines(content)
    already = {
        kind: any(
            HIDE_PREFIX[kind] in line or PREHIDDEN_PREFIX[kind] in line
            for line in lines
        )
        for kind in HIDE_PREFIX
    }
    hidden = dict(already)
    prehidden = {
        kind: any(PREHIDDEN_PREFIX[kind] in line for line in lines)
        for kind in HIDE_PREFIX
    }
    pending: str | None = None
    remaining = 0
    result: list[str] = []

    for raw in lines:
        stripped = raw.strip()
        if "Loading Linux %s ..." in raw:
            pending, remaining = "linux", 20
        elif "Loading initial ramdisk ..." in raw:
            pending, remaining = "initrd", 20

        if pending and not hidden[pending] and ECHO_MESSAGE_RE.fullmatch(stripped):
            indent = raw[: len(raw) - len(raw.lstrip())]
            newline = "\n" if raw.endswith("\n") else ""
            result.append(f"{indent}{HIDE_PREFIX[pending]}{stripped}{newline}")
            hidden[pending] = True
            pending = None
            continue
        if pending and not hidden[pending] and stripped.startswith("#"):
            commented = stripped[1:].strip()
            if ECHO_MESSAGE_RE.fullmatch(commented):
                indent = raw[: len(raw) - len(raw.lstrip())]
                newline = "\n" if raw.endswith("\n") else ""
                result.append(
                    f"{indent}{PREHIDDEN_PREFIX[pending]}{stripped}{newline}"
                )
                hidden[pending] = True
                prehidden[pending] = True
                pending = None
                continue
        if pending and not hidden[pending] and "$message" in raw:
            raise TransformError(
                f"unsupported command prints the {pending} loading message"
            )
        boundary = (
            pending == "linux" and re.match(r"^linux(?:efi)?\s", stripped)
        ) or (
            pending == "initrd" and re.match(r"^initrd(?:efi)?\s", stripped)
        )
        if pending and not hidden[pending] and boundary:
            indent = raw[: len(raw) - len(raw.lstrip())]
            result.append(
                f"{indent}{PREHIDDEN_PREFIX[pending]}__MISSING__\n"
            )
            hidden[pending] = True
            prehidden[pending] = True
            pending = None

        result.append(raw)
        if pending:
            remaining -= 1
            if remaining <= 0:
                pending = None

    missing = [kind for kind, value in hidden.items() if not value]
    if missing:
        raise TransformError("unsupported /etc/grub.d/10_linux layout; missing " + ", ".join(missing))
    return "".join(result), prehidden


def restore_grub_messages(content: str) -> str:
    lines = split_lines(content)
    restored = {kind: False for kind in HIDE_PREFIX}
    result: list[str] = []
    for raw in lines:
        replaced = False
        for kind in HIDE_PREFIX:
            for prefix in (HIDE_PREFIX[kind], PREHIDDEN_PREFIX[kind]):
                pattern = re.compile(rf"^(?P<indent>\s*){re.escape(prefix)}(?P<body>.*?)(?P<newline>\n?)$")
                match = pattern.match(raw)
                if match:
                    if match.group("body") != "__MISSING__":
                        result.append(match.group("indent") + match.group("body") + match.group("newline"))
                    restored[kind] = True
                    replaced = True
                    break
            if replaced:
                break
        if not replaced:
            result.append(raw)
    return "".join(result)


def audit_kind(kind: str, content: str) -> bool:
    if kind == "theme":
        return theme_value(content) == "spinner"
    if kind == "hooks":
        matches = [HOOKS_RE.match(line) for line in content.splitlines()]
        matches = [match for match in matches if match]
        if len(matches) != 1:
            return False
        hooks = shlex.split(matches[0].group("body"), posix=True)
        return hooks.count("plymouth") == 1 and "udev" in hooks and \
            hooks.index("plymouth") == hooks.index("udev") + 1
    if kind == "cmdline":
        matches = [CMDLINE_RE.match(line) for line in content.splitlines()]
        matches = [match for match in matches if match]
        if len(matches) != 1:
            return False
        tokens = cmdline_tokens(matches[0].group("body"))
        return tokens.count("quiet") == 1 and tokens.count("splash") == 1
    return all(
        HIDE_PREFIX[kind] in content or PREHIDDEN_PREFIX[kind] in content
        for kind in HIDE_PREFIX
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("apply", "remove", "audit"))
    parser.add_argument("kind", choices=("theme", "hooks", "cmdline", "grub-script"))
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path, nargs="?")
    parser.add_argument("--previous-theme", default="__ABSENT__")
    parser.add_argument("--remove-quiet", action="store_true")
    parser.add_argument("--remove-splash", action="store_true")
    parser.add_argument("--previous-hook-index", type=int)
    args = parser.parse_args()
    content = read(args.source)

    try:
        if args.operation == "apply":
            if args.kind == "theme":
                previous = theme_value(content)
                output = set_theme(content, "spinner")
                print(f"THEME_PREVIOUS={previous or '__ABSENT__'}")
            elif args.kind == "hooks":
                output, added, old_index = transform_hooks(content)
                print(f"MKINITCPIO_ADDED={int(added)}")
                print(f"PLYMOUTH_HOOK_PREVIOUS_INDEX={old_index}")
            elif args.kind == "cmdline":
                output, quiet_added, splash_added = transform_cmdline(content)
                print(f"QUIET_ADDED={int(quiet_added)}")
                print(f"SPLASH_ADDED={int(splash_added)}")
            else:
                output, prehidden = hide_grub_messages(content)
                print(f"LINUX_ECHO_PREHIDDEN={int(prehidden['linux'])}")
                print(f"INITRD_ECHO_PREHIDDEN={int(prehidden['initrd'])}")
        elif args.operation == "remove":
            if args.kind == "theme":
                previous = None if args.previous_theme == "__ABSENT__" else args.previous_theme
                output = set_theme(content, previous)
            elif args.kind == "hooks":
                if args.previous_hook_index is None:
                    raise TransformError("previous hook index is required for removal")
                output, _, _ = transform_hooks(content, previous_index=args.previous_hook_index)
            elif args.kind == "cmdline":
                output, _, _ = transform_cmdline(
                    content,
                    remove_quiet=args.remove_quiet,
                    remove_splash=args.remove_splash,
                )
            else:
                output = restore_grub_messages(content)
        else:
            return 0 if audit_kind(args.kind, content) else 1
    except TransformError as error:
        parser.exit(3, f"plymouth-transform: {error}\n")

    if args.destination is None:
        parser.error("destination is required for apply/remove")
    write(args.destination, output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
