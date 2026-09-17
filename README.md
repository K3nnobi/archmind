# ArchMind 1.5.18 — Firefox Color Emoji Fix

ArchMind is a terminal-based toolkit for Arch Linux and GNOME. It includes the
responsive AFI console, the classic Manager, system diagnostics, backup and
restoration, package profiles, maintenance tools, desktop integrations, and
optional gaming and Wine compatibility patches.

## What changed in 1.5.18

- Optional Package Center patch for ChatGPT color emoji in Firefox.
- Existing Firefox user.js and userContent.css are backed up and preserved.
- Status and removal are available through Rollback Center.
- Fully restart Firefox after applying or removing the patch.

- All current installer screens, prompts, menus, dialogs, reports, helpers, and
  operational messages are in English.
- The classic Manager, AFI runtime, legacy Zsh modules, and auxiliary toolkit
  now use the same language.
- Current documentation and the translation auditor were updated for this
  release.
- Confirmation prompts use `[y/N]` and accept `y` or `yes`.
- Internal backup mode names and established archive filename patterns remain
  unchanged so backups created by earlier releases continue to work.

See [RELEASE-NOTES-1.5.18.md](RELEASE-NOTES-1.5.18.md) for the release scope and
validation details.

## Recommended installation

Quick installation (as your normal user, without `sudo`):

```bash
curl -fsSL https://github.com/K3nnobi/archmind/raw/main/get | bash
```

The bootstrap downloads version 1.5.18, verifies its SHA-256 and starts the
interactive installer. It also works from a TTY. Review [the bootstrap](get)
before running it if you prefer.

### Download and verify manually

Download the single-file installer from the
[1.5.18 public release](https://github.com/K3nnobi/archmind/releases/tag/v1.5.18).
Run the following in a terminal on an installed Arch Linux system, as your
normal user (not from the installer ISO and not as root):

```bash
(
  set -eu
  mkdir -p "$HOME/Downloads"
  cd "$HOME/Downloads"
  curl -fL --retry 3 -o ArchMind-1.5.18-public-Installer.run \
    https://github.com/K3nnobi/archmind/releases/download/v1.5.18/ArchMind-1.5.18-public-Installer.run
  printf '%s  %s\n' \
    '9de5bcc1e7e243b74a80e676a7cf41188a11f57e23aac9efa8da98ba1b6990e9' \
    'ArchMind-1.5.18-public-Installer.run' | sha256sum -c -
  bash ArchMind-1.5.18-public-Installer.run --check
  bash ArchMind-1.5.18-public-Installer.run
)
```

The installer verifies its embedded archive, displays the installation plan,
asks for confirmation, installs ArchMind, and opens `archmind-console` after a
successful installation. Optional package modules may request administrator
authentication when they invoke Pacman or an AUR helper.

Do not run the installer with `sudo` or as root.

## Installation from the portable archive

```bash
cd "$HOME/Downloads"
tar -xzf ArchMind-1.5.18-public.tar.gz
cd ArchMind-1.5.18

./install.sh --check
./install.sh --dry-run
./install.sh
```

Then start the console:

```bash
export PATH="$HOME/.local/bin:$PATH"
archmind-console
```

The interactive installer includes a staged progress bar with a minimum visual
duration of five seconds. Use `./install.sh --no-progress` to disable it.

## Main commands

```text
archmind-console    Open the responsive AFI interface
archmind            Compatible shortcut for the main console
archmind-monitor    Open the read-only live system monitor
archmind-manager    Open the classic Manager when installed
```

The included Zsh shortcuts are `pacinstall` (`sudo pacman -S`) and
`pacupdate` (`sudo pacman -Syu`). These names avoid masking commands named
`install` and `update`.

## Installed data layout

User-facing ArchMind data is consolidated under `~/ArchMind`:

```text
~/ArchMind/
├── Backups/
├── Config/
├── Installer-Backups/
├── Logs/
├── Projects/
└── State/
```

The application runtime is installed in `~/ArchMind/System/Core` and
`~/ArchMind/System/Toolkit`, with compatibility links at the former locations.
Launchers are installed in `~/.local/bin`, and desktop integration files use
the standard XDG locations required by GNOME.

The Home Zsh organizer only moves known loose `.zsh` candidates after review,
creates a safety copy, and never overwrites an existing destination.

## Package profiles

- **Base:** GNOME/Nautilus integration, fonts, codecs, PipeWire, Flatpak,
  maintenance tools, and New Document templates.
- **Terminal:** GNOME Terminal, Zsh, Powerlevel10k, plugins, and CLI utilities.
- **Gaming:** Steam, Wine, Winetricks, Protontricks, Gamescope, Lutris,
  MangoHud, Discord, and optional GameMode integration.
- **Audio:** EasyEffects, LV2 plugins, PipeWire JACK, and Audacity.
- **Development:** Python, Pip/Pipx, Node.js, Docker, Git, and development tools.

Video drivers are intentionally not selected automatically. Install the driver
appropriate for the target NVIDIA, AMD, or Intel hardware.

## Safety model

- Backup and restore operations validate paths and archive contents.
- Destructive or system-wide actions require explicit confirmation.
- Optional integrations report failures without aborting an unrelated full
  restoration.
- Proton prefixes are never mixed with regular Wine prefixes.
- Boot, NVIDIA, GNOME, and input patches keep their own rollback state where
  supported.
- The Maintenance Center audits cleanup targets before removing anything.

## Requirements

- Arch Linux
- Zsh
- Python 3.10 or newer for AFI reports, Storage, Updates, and Live Monitor
- `pacman-contrib` for official repository update checks
- `yay` or `paru` only when AUR packages are requested
- GNOME-specific features require a GNOME session

## Verification

From the extracted directory:

```bash
./install.sh --check
python3 -B payload/archmind/tools/translation-audit.py payload/archmind --strict
python3 -B payload/archmind/tools/translation-audit.py payload/toolkit --strict
```

Historical release notes are kept as an archive of earlier builds. The active
1.5.18 interface, installer, runtime, toolkit, helpers, and current documentation
are maintained in English.
