#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly PACKAGE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly VERSION="$(<"$PACKAGE_ROOT/VERSION")"
readonly PACKAGE_NAME="ArchMind-${VERSION}"
readonly TEMPLATE="$PACKAGE_ROOT/installer/ArchMind-Installer.run.in"
readonly OUTPUT="${1:-$PACKAGE_ROOT/../ArchMind-${VERSION}-Installer.run}"

[[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || {
    printf '[ERROR] The destination already exists: %s\n' "$OUTPUT" >&2
    exit 1
}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][[:alnum:]-]+)?$ ]] || exit 1
bash "$PACKAGE_ROOT/install.sh" --check

temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "$temporary_directory"' EXIT

[[ "$(basename -- "$PACKAGE_ROOT")" == "$PACKAGE_NAME" ]] || {
    printf '[ERROR] The directory must be named %s.\n' "$PACKAGE_NAME" >&2
    exit 1
}
[[ -f "$TEMPLATE" ]] || {
    printf '[ERROR] Installer template not found.\n' >&2
    exit 1
}

archive="$temporary_directory/${PACKAGE_NAME}.tar.gz"
tar --sort=name \
    --exclude='__pycache__' --exclude='*.pyc' \
    --mtime='2026-09-02 00:00:00 UTC' \
    --owner=0 --group=0 --numeric-owner \
    -C "$(dirname -- "$PACKAGE_ROOT")" \
    -czf "$archive" "$PACKAGE_NAME"

archive_sha256="$(sha256sum "$archive" | awk '{print $1}')"
sed \
    -e "s/@VERSION@/${VERSION}/g" \
    -e "s/@ARCHIVE_SHA256@/${archive_sha256}/g" \
    "$TEMPLATE" > "$OUTPUT"
dd if="$archive" of="$OUTPUT" bs=1M oflag=append conv=notrunc status=none
chmod 755 "$OUTPUT"

printf '[ OK ] Installer created: %s\n' "$OUTPUT"
printf '[ OK ] SHA-256: %s\n' "$(sha256sum "$OUTPUT" | awk '{print $1}')"
