# ArchMind 1.5.18 — review for public distribution

## Scope

Reviewed the 1.5.18 source tree and independently extracted both public
distribution files. This review concerns personal information in files being
distributed; it is not a security audit of the application or its dependencies.

## Changes

- Removed the personal account and computer names from release history and
  test fixtures; replaced fixture values with generic examples.
- Replaced a personal author credit in the packaged runtime with a generic
  contributor label. This was found during the follow-up review.
- Replaced the installer check for one named account with a check for fixed
  `/home/<username>/` paths anywhere in the application payload.
- Retained the migration test using the fictional account `legacyuser`.
- Renamed bundled Zsh shortcuts `install` and `update` to `pacinstall` and
  `pacupdate`, so they do not mask other commands.
- Kept the original 1.5.18 release separate; publish only the files with the
  `-public` suffix.

## Checks completed

- Inspected source file names and contents for the known personal names,
  machine and disk identifiers, fixed home paths, private key headers, and
  common API token shapes.
- Checked for shipped backups, history, `.env` files, SSH keys, Wine and
  Firefox profiles, and Git metadata. None were present in the source tree.
- Confirmed the archive has relative paths and root ownership metadata.
- Passed installer integrity and syntax validation, seven maintenance tests,
  eleven simulated installer safety tests, the Zsh alias check, and the full
  installation/restoration regression script.
- Verified the `.run` and `.tar.gz`, extracted both, compared their contents
  byte for byte against the reviewed source and repeated the identifier scan.
- No occurrences of the known personal names or identifiers remained in
  either extracted distribution.

## Distribution files

| File | SHA-256 |
| --- | --- |
| `ArchMind-1.5.18-public.tar.gz` | `ec5572d18cb5c34aaf01a4fec8113837e7a8666cdaadb9ad7e64d8eb3017595f` |
| `ArchMind-1.5.18-public-Installer.run` | `9de5bcc1e7e243b74a80e676a7cf41188a11f57e23aac9efa8da98ba1b6990e9` |

The package contains generic test data, GNOME extension identifiers, and
upstream project links. These are not the user's account details. Do not
publish a separately created ArchMind backup or a copy of an installed
`~/ArchMind` directory: those can contain actual usernames, computer names,
package inventories, and personal configuration generated at runtime.
