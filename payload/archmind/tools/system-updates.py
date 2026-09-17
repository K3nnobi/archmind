#!/usr/bin/env python3
"""Check updates separately from explicitly confirmed interactive upgrades."""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from runtime_files import private_directory, safe_text


def query(command, env=None, empty_code=None):
    try:
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace",
                                timeout=90, env={**os.environ, "LC_ALL": "C", **(env or {})}, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"ok": False, "lines": [], "message": f"Query unavailable: {safe_text(str(error))}"}
    stdout = result.stdout or ""
    stderr = result.stderr or ""
    output = [safe_text(line) for line in stdout.splitlines() if line.strip()]
    if result.returncode == 0 or (empty_code is not None and result.returncode == empty_code and not output and not stderr.strip()):
        return {"ok": True, "lines": output, "message": "Updates available" if output else "No updates available"}
    return {"ok": False, "lines": output,
            "message": f"Query failed (exit {result.returncode}): {safe_text(stderr.strip())[:600]}"}


def unavailable(message):
    return {"ok": False, "lines": [], "message": message}


def installed_versions():
    """Return a read-only package snapshot for post-transaction comparison."""
    if not shutil.which("pacman"):
        return {}
    result = query(["pacman", "-Q"])
    versions = {}
    if result["ok"]:
        for line in result["lines"]:
            fields = line.split(None, 1)
            if len(fields) == 2:
                versions[fields[0]] = fields[1]
    return versions


def run_update_guardian(changed):
    guardian = Path(__file__).with_name("update-guardian.py")
    if not guardian.is_file():
        print("Update Guardian is unavailable; run ArchMind Doctor manually.")
        return
    command = [sys.executable, "-B", str(guardian)]
    if changed:
        command.extend(("--changed", *sorted(changed)))
    print("\nRunning the post-update Update Guardian...")
    try:
        subprocess.run(command, check=False)
    except OSError as error:
        print(f"Could not start Update Guardian: {error}")


def run_post_update_doctor():
    doctor = Path(__file__).with_name("post-update-doctor.zsh")
    if not doctor.is_file() or not shutil.which("zsh"):
        print("Post-update ArchMind Doctor is unavailable; run it from the console later.")
        return
    print("\nRunning a quick, read-only ArchMind Doctor check...")
    try:
        subprocess.run(["zsh", str(doctor)], check=False)
    except OSError as error:
        print(f"Could not start ArchMind Doctor: {error}")


def collect_updates():
    results = {}
    if shutil.which("checkupdates"):
        fd = None
        try:
            directory, fd = private_directory(("Temp", "Updates"), create=True)
            # Unique private database: never refresh the live DB in isolation.
            with tempfile.TemporaryDirectory(prefix="check-", dir=directory) as temp:
                results["Official repositories"] = query(["checkupdates", "--nocolor"],
                    env={"CHECKUPDATES_DB": temp + "/db"}, empty_code=2)
        except (OSError, ValueError) as error:
            results["Official repositories"] = unavailable(str(error))
        finally:
            if fd is not None:
                os.close(fd)
    else:
        results["Official repositories"] = unavailable("Fresh check unavailable: install pacman-contrib (provides checkupdates). No package was installed.")
    helper = next((name for name in ("yay", "paru") if shutil.which(name)), None)
    results["AUR"] = query([helper, "-Qua"]) if helper else unavailable("No supported AUR helper (yay or paru) is installed")
    results["Flatpak"] = query(["flatpak", "remote-ls", "--updates", "--columns=application,branch"]) if shutil.which("flatpak") else unavailable("Flatpak is not installed")
    return results, helper


def display(results):
    print("ArchMind / System Updates\n")
    print("Checks do not install or upgrade packages. Failed checks are not zero updates.\n")
    for name, result in results.items():
        print(f"{name}: {result['message']}")
        for line in result["lines"]:
            print("  " + line)
        print()


def interactive(results, helper, input_fn=input):
    if os.geteuid() == 0:
        print("Run ArchMind as your normal user. Upgrades request sudo only when needed.")
        return 1
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("Interactive terminal required. No packages were changed.")
        return 1
    print("1  Official repositories: sudo pacman -Syu")
    if helper:
        print(f"2  Official repositories + AUR: {helper} -Syu")
    if shutil.which("flatpak"):
        print("3  Flatpak: flatpak update")
    print("Enter / any other key: return without changes")
    selection = input_fn("Choose an update scope: ").strip()
    if selection == "1":
        needed, command = ("Official repositories",), ["sudo", "pacman", "-Syu"]
    elif selection == "2" and helper:
        needed, command = ("Official repositories", "AUR"), [helper, "-Syu"]
    elif selection == "3" and shutil.which("flatpak"):
        needed, command = ("Flatpak",), ["flatpak", "update"]
    else:
        print("Cancelled. No packages were changed.")
        return 0
    if not all(results[name]["ok"] for name in needed):
        print("Update blocked: a required check failed or is unavailable. Resolve it and check again.")
        return 1
    if not all(shutil.which(name) for name in (command[:2] if selection == "1" else command[:1])):
        print("Update command unavailable. No packages were changed.")
        return 1
    print("\nReview Arch Linux news and keep a current backup before upgrading.")
    print("Do not close the terminal during a package transaction. Reboot may be required.")
    print("AUR packages run third-party build scripts; review the helper's prompts.")
    print("The final transaction can differ from this preview; review the package manager's confirmation.")
    print("Command: " + " ".join(command))
    if input_fn("Type UPDATE to continue (anything else cancels): ").strip() != "UPDATE":
        print("Cancelled. No packages were changed.")
        return 0
    # Keep the package manager's own confirmations. Never --noconfirm.
    before = installed_versions() if selection in ("1", "2") else {}
    try:
        completed = subprocess.run(command, check=False)
    except OSError as error:
        print(f"Could not start the update: {error}")
        return 1
    if completed.returncode:
        print(f"Update did not complete successfully (exit {completed.returncode}). Review the output; no success was recorded.")
        return completed.returncode if completed.returncode > 0 else 1
    print("Package manager finished successfully. Review its messages for any required follow-up.")
    after = installed_versions() if selection in ("1", "2") else {}
    changed = {
        package for package in set(before) | set(after)
        if before.get(package) != after.get(package)
    }
    run_update_guardian(changed)
    run_post_update_doctor()
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interactive", action="store_true")
    args = parser.parse_args()
    try:
        print("Checking update sources; Ctrl+C cancels the check...", flush=True)
        results, helper = collect_updates()
        display(results)
        return interactive(results, helper) if args.interactive else (0 if results["Official repositories"]["ok"] else 1)
    except (KeyboardInterrupt, EOFError):
        print("\nInterrupted. If a package transaction had started, inspect its output before retrying.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
