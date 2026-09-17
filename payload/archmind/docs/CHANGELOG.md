# Changelog

## 1.5.18

- Optional Firefox / ChatGPT Color Emoji Fix with profile detection, safety
  copies, idempotent managed CSS, preference management, status, and rollback.

## 1.5.17

- Completed English translation of the installer, classic Manager, legacy
  modules, toolkit, optional integrations, and runtime messages.
- Confirmation prompts now consistently use `[y/N]` while retaining compatible
  internal identifiers for existing backups.

## 1.5.16

- Optional Caps Lock No Delay patch based on keyd.
- Conservative integration with backup and refusal of conflicting remappings.
- Dedicated status and rollback without automatic removal of the keyd package.

## 1.5.15

- Optional GNOME Drag Hover patch for Dash to Dock in Wayland sessions.
- 400 ms hover over dock icons or visible parts of windows during DnD.
- Anchor and marker validation, atomic writes, and snapshots with hashes.
- Removal/restoration refuses files updated or modified after patching.
- Doctor and Rollback Center recognize the independent module.

## 1.5.14

- Optional Wine Compatibility Pack kept separate from Gaming Profile.
- Mandatory backup before changing existing prefixes and per-verb logs.
- Visual C++ 14.x detection before installing `vcrun2022`.
- DXVK, Windows 7-Zip, and dotnet48 remain independent optional actions.
- Proton/Steam prefixes and automatic `--force` usage are refused.
- Rollback Center catalogs snapshots from the Wine module.

## 1.5.13

- New Maintenance Center with seven reusable modules.
- Update Guardian detects internal and external package changes.
- Task center records reboot, GNOME session, and post-update repairs.
- Hardware Profile hides incompatible integrations in the AFI.
- Rollback Center limits restoration to registered reversible modules.
- Safe Cleanup separates auditing, confirmation, and execution by category.
- Backup Catalog compares contents and packages without extracting the archive.
- Normal, Gaming, Quiet, and Diagnostic profiles control Live Monitor.

## 1.5.12

- Optional NVIDIA Vibrance module with user service and variable intensity.
- Base Profile includes Plymouth without applying boot configuration.
- Standalone, auditable, idempotent, reversible Plymouth patch with rollback.
- AFI exposes status, application, and removal for both new features.

## 1.5.11

- Gaming Profile integrates GameMode with Blur My Shell without replacing hooks.
- Originally enabled extension state is restored after the last client exits.
- Package Center provides configuration, testing, status, and removal.
- Backup/restoration preserves policy and rewrites paths for the current user.

## 1.5.10

- Installation progress follows real stages with a five-second minimum in TTY.

## 1.5.8

- Single installer with confirmation, cancellation, and AFI launch after success.
- Conservative organization of loose .zsh files with safety copy and undo.
- Recovery includes final shell, Config, and .desktop changes.
- Hidden-link backup and restoration use portable content between users.
- Code and runtime centralized in `~/ArchMind/System`.
- Preferences, aliases, and Powerlevel10k moved to `~/ArchMind/Config`.
- Transactional migration from the 1.5.6 tree with compatibility links.
- New backups preserve `~/ArchMind/Config`; old backups restore `.zsh_aliases`
  and `.p10k.zsh` to the new destinations.

## 1.5.6

- Startup panel walls sized from each panel's longest sentence.
- Removed fixed widths from ArchMind and Fastfetch.
- Side-by-side mode now depends on the real width of both panels.
- Corners, separators, and vertical bars remain in the same column.

## 1.5.5

- Fixed displaced bars and overlapping text in the combined startup.
- Removed CSI/OSC controls from Fastfetch output before rendering.
- ArchMind now aligns keys and values without moving the cursor.

## 1.5.4

- Compact Fastfetch shown beside ArchMind in wide terminals.
- Panels automatically stack below 110 columns.
- Removed duplicate ASCII logo while retaining 12 essential details.
- Personal Fastfetch settings are preserved and ignored only at startup.

## 1.5.3

- Fixed near-black startup panel contrast in GNOME Terminal.
- Replaced missing `ARCHMIND_ANSI_*` references with the official palette.
- Added color fallbacks for safe startup.
- Memory detection now works independently of locale.
- Startup footer points to `archmind-console`.

## 1.5.2

- `gnome-rounded-blur` support for correct Blur My Shell corners.
- Post-install diagnosis through `rounded-blur-found` and logout/login notice.
- GNOME restoration reinstalls the library for old backups.
- Papirus-Dark receives yellow folders through `papirus-folders`.
- No CSS workaround was added to mask blur clipping.

## 1.5.1

- Idempotent Nautilus integration in Base Profile and Package Center.
- `.exe` thumbnails through `icoextract`, `python-pillow`, and `icoutils`.
- Folders before files and transparent thumbnails through GTK4.
- Backup and restoration of `~/.local/share/thumbnailers`.
- Optional Nautilus failures do not interrupt profiles or restorations.

## 1.5.0

- AFI redraws automatically when the terminal is resized.
- Full, standard, and compact layouts with a scrollable menu.
- Minimum-size warning without artifacts or off-screen borders.
- Geometry read directly from the PTY and frozen per frame.
- Viewers, notifications, and dialogs now respond to resizing.

## 1.4.2

- Restoration by situation fixed and confirmed before execution.
- Resilient recovery of official, AUR, and Flatpak packages with reports.
- Zsh plugins, Powerlevel10k, and `~/.zsh_aliases` ensured after restoration.
- Protection against project downgrade through old backups.
- Portable installer configures PATH for Bash and Zsh.
