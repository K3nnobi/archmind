# Changelog

## 1.5.18

- Distributes the optional Firefox / ChatGPT Color Emoji Fix in Package Center.

## 1.5.17

- Toolkit runtime, modules, help, and documentation completed in English.

## 1.5.16

- Package Center distributes the optional Caps Lock No Delay patch.
- Rollback Center recognizes keyd configuration backups.

## 1.5.15

- Runtime exposes the optional GNOME Drag Hover manager in Package Center.
- Doctor and Rollback Center detect the patch and Dash to Dock updates.

## 1.5.14

- Distributes the independent Wine Compatibility Pack.
- Gaming Profile includes basic Winetricks tools without automatically applying
  runtimes to any prefix.

## 1.5.13

- Runtime distributes Maintenance Center and its persistent services.
- Confirmed updates call Guardian and Doctor after success.
- Backups recognize JSON manifests and preserve the operating profile.

## 1.5.12

- Base Profile includes Plymouth without applying the boot patch.
- Gaming Profile offers NVIDIA Vibrance only on compatible hardware.

## 1.5.11

- Gaming Profile configures the optional GameMode + Blur My Shell integration.

## 1.5.10

- Distribution includes visual progress in the interactive installer.

## 1.5.8

- Backup stores real aliases/Powerlevel10k content rather than absolute links.
- Restoration recreates missing hidden links and includes Imported-Home batches.
- Runtime moved to `~/ArchMind/System/Toolkit`.
- `Backups` and `Projects` directories normalized to plural names.
- Zsh configuration centralized in `~/ArchMind/Config/Zsh`.

## 1.5.6

- Distributes startup panels dynamically sized from their contents.

## 1.5.5

- Fixes Fastfetch rendering inside the startup panel.

## 1.5.4

- Distributes the compact, responsive ArchMind + Fastfetch startup.

## 1.5.3

- Distributes the startup panel with corrected contrast and memory detection.

## 1.5.2

- Base Profile includes `gnome-rounded-blur`, `papirus-icon-theme`, and
  `papirus-folders`.
- GNOME restoration reapplies rounded blur and yellow Papirus-Dark folders.

## 1.5.1

- Base Profile installs and configures Nautilus integration.
- Backup includes local thumbnailers and restoration reinstalls dependencies.

## 1.5.0

- Distributes the responsive AFI and unified Manager 1.5.0.
- Preserves preferences when updating from version 1.4.2.

## 1.4.2

- Backup includes `~/.zsh_aliases` and preserves installed launchers.
- Restoration filters unavailable names before invoking Pacman or Yay.
- PATH and Zsh plugin configuration work in Bash and Zsh.

## 2.0.0

- Modular structure.
- Full `.archmind` backup.
- ArchMind project backup and restoration.
- Base, Terminal, Gaming, Development, and Audio profiles.
- Zsh, Powerlevel10k, and plugins in Terminal Profile.
- Persistent profile.
- First ArchMind Doctor version.

## 2.0.1

- Fixed path resolution when executed through a symbolic link.
- Installer now shows a direct executable test.
