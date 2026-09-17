# ArchMind 1.5.10 — test build

Baseline: 1.5.9. Target: Arch Linux with GNOME. No operating-system migration.

## Approved monitor integration

The integrated `tools/live-monitor.py` is byte-for-byte identical to the approved
ArchMind Monitor 0.1.0. SHA-256:

`0269cea004257c97de1d009bdbef95424c0250119329307b3b1b2e5e92776991`

Default refresh remains one second. No changes to layout or the N/C shortcuts.
`System Monitor → Live Monitor` and the `archmind-monitor` command run the same
file. Nested curses/AFI handoff releases and re-enters the alternate screen.

## System Updates

- Entering the action checks availability; it never installs by itself.
- Official checks use checkupdates with a new private temporary database beneath
  `~/ArchMind/Temp/Updates`, removed after the query. Exit 2 means no updates;
  network failures/timeouts are not treated as empty successful results.
- AUR checks support yay/paru; Flatpak checks are optional.
- Upgrade choices: official (`sudo pacman -Syu`), official + AUR (`yay -Syu` or
  `paru -Syu`), or Flatpak (`flatpak update`).
- The chosen scope must have successful required checks. A normal-user TTY and
  the exact confirmation `UPDATE` are required, regardless of the AFI optional
  confirmation preference. Native package-manager prompts are preserved.
- No automatic root execution, package installation, reboot, lock-file deletion,
  forced dependency resolution or automatic retry of failed transactions.
- The query preview is not a frozen transaction plan. Users review the final
  package-manager confirmation, Arch news, package scripts and backup status.

Primary reference: [Arch checkupdates manual](https://man.archlinux.org/man/checkupdates.8.en)
and [Pacman manual](https://man.archlinux.org/man/pacman.8.en).

## ArchMind Doctor

- Quick/Full/Pacman/Audio results are persisted after their checks complete.
- View Report only reads the newest saved report. With no report, it asks for a
  diagnosis first. Merely entering the Doctor menu no longer runs network checks.
- Missing commands and failed queries are unavailable, not healthy. Full
  diagnosis includes its extra check failures in the final result.
- Private directory `~/ArchMind/Logs/Doctor` (0700), reports (0600), atomic
  publication with unique timestamps, no overwrite of older reports.
- Symlinked runtime directories and non-regular/latest symlink files are refused.
- Backup and restore cover Doctor reports in both Manager and Toolkit paths.
  Import is additive; existing files are preserved. Report-save failures do not
  erase old files or pretend the current report was saved.
- Reports can include system details. Review before sharing. No credentials,
  environment dumps or process command lines are intentionally collected.

## Storage and language

Storage uses the monitor collector (statvfs) and prints its own English labels,
not localized df column headers. Decimal GB and binary GiB appear together.
Available uses f_bavail; shared Btrfs subvolumes are not summed. Filesystem
metadata/quotas can still limit actual writable space.

The AFI menus, dialogs and services are translated to English. The classic
Manager, installation utilities and third-party tools retain their prior
language. The approved monitor layout is unchanged.

## Validation and remaining real-machine checks

All package-manager tests use mocks; no real system upgrade is performed.
Install/restore safety tests use disposable copies and, where necessary,
explicit root-environment simulation. They do not prove a live GNOME session
or physical NVIDIA/Btrfs hardware works on every machine.

Run from this package directory:

```bash
bash install.sh --check
python3 -B tests/test-integration.py
python3 -B tests/test-live-monitor.py
python3 -B tests/test-monitor-handoff.py
bash tests/test-stable.sh
ARCHMIND_TEST_SIMULATE=1 python3 -B tests/test-install-safety.py
ARCHMIND_TEST_SIMULATE=1 python3 -B tests/test-run-flow.py
python3 -B tests/test-responsive.py
```

On the user's machine: confirm monitor entry/return, create a Doctor report and
reopen it after restarting AFI, compare Storage with Nautilus at the same time,
and check Updates **without confirming installation** for the initial test.
Only perform an actual upgrade when ready, with a current backup; don't close
the terminal mid-transaction. Preserve the 1.5.9 installer for rollback.
