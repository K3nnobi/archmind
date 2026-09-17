# ArchMind 1.5.17 Release Notes

## Scope

Version 1.5.17 completes the English migration of the active ArchMind user
experience. It translates the self-extracting installer, portable installer,
AFI console, classic Manager, legacy Zsh commands, toolkit modules, reports,
desktop helpers, and current project documentation.

## Compatibility

The translation changes visible text and confirmation input only. Internal
backup mode identifiers and existing archive filename patterns were preserved
to maintain compatibility with backups created by earlier ArchMind versions.

Confirmation prompts now use `[y/N]` and accept `y` or `yes`. The default remains
No when Enter is pressed without a response.

## Translation safeguards

The translation auditor now scans Python and installer-template files in
addition to shell, Zsh, configuration, and documentation formats. The auditor
excludes only its own detection vocabulary and the dedicated Portuguese-search
helper.

## Validation targets

- Bash and Zsh syntax validation
- Python syntax compilation
- strict translation audit for the ArchMind runtime and auxiliary toolkit
- payload checksum verification
- self-extracting installer build and verification
- portable archive extraction and integrity verification
- isolated installation, restoration, maintenance, Wine, GameMode, GNOME, and
  responsive AFI tests

## Safety

Run ArchMind as a normal user. The base installer must not be executed with
`sudo`; optional modules request elevated privileges only for the specific
system package or configuration step that requires them.
