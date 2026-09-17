#!/usr/bin/env bash
# Never source a candidate file. Matching content is not proof it is unused.
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly CORE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly DATA_ROOT="$HOME/ArchMind"
readonly IMPORT_ROOT="$DATA_ROOT/Config/Zsh/Imported-Home"
readonly NAMES=(aliases.zsh colors.zsh functions.zsh git.zsh icons.zsh
    monitor.zsh ollama.zsh python.zsh startup.zsh theme.zsh)
candidates=()
references=()
saved_dir=""
import_dir=""
moved=()

fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

validate_parents() {
    local target="$1"
    while [[ "$target" != "$HOME" && "$target" != / ]]; do
        [[ ! -L "$target" ]] || fail "Directory link not accepted: $target"
        [[ ! -e "$target" || -d "$target" ]] || fail "Not a directory: $target"
        target="${target%/*}"
    done
}

collect_references() {
    local file directory
    for file in .zshrc .zshenv .zprofile .zlogin .zlogout .profile .bashrc .bash_profile; do
        [[ ! -e "$HOME/$file" ]] || references+=("$HOME/$file")
    done
    for directory in "$HOME/.config/zsh" "$DATA_ROOT/Config/Zsh/modules"; do
        [[ -d "$directory" ]] || continue
        while IFS= read -r -d '' file; do references+=("$file"); done \
            < <(find "$directory" -type f -print0)
    done
    for file in "${NAMES[@]}"; do
        [[ ! -f "$HOME/$file" ]] || references+=("$HOME/$file")
    done
}

has_reference() {
    local name="$1" file
    [[ -n "${ZDOTDIR:-}" ]] && return 0
    for file in "${references[@]}"; do
        [[ "$file" != "$HOME/$name" ]] || continue
        # An unreadable source means we cannot safely classify the candidate.
        [[ -r "$file" && -f "$file" ]] || return 0
        grep -qF -- "$name" "$file" && return 0
        grep -qE 'ZDOTDIR|(^|[[:space:];])(source|\.)[[:space:]].*[*?]' "$file" && return 0
    done
    return 1
}

known_duplicate() {
    local source="$1" known directory
    for directory in "$CORE/core" "$CORE/theme" "$CORE/modules" "$DATA_ROOT/Config/Zsh/modules"; do
        [[ -d "$directory" ]] || continue
        while IFS= read -r -d '' known; do
            cmp -s -- "$source" "$known" && return 0
        done < <(find "$directory" -type f -name '*.zsh' -print0)
    done
    return 1
}

scan() {
    local name source
    collect_references
    printf '\nConservative organization of Home .zsh files\n'
    for name in "${NAMES[@]}"; do
        source="$HOME/$name"
        [[ -e "$source" || -L "$source" ]] || continue
        if [[ -L "$source" || ! -f "$source" || ! -r "$source" ]]; then
            printf '[KEEP] %s: link or non-regular/unreadable file.\n' "$name"
        elif ! known_duplicate "$source"; then
            printf '[KEEP] %s: custom or unrecognized content.\n' "$name"
        elif has_reference "$name"; then
            printf '[KEEP] %s: reference or dynamic loading detected.\n' "$name"
        else
            candidates+=("$name")
            printf '[CANDIDATE] %s: identical copy with no detected reference.\n' "$name"
        fi
    done
    printf '\nThe analysis is static: indirect references may not appear.\n'
    printf 'No file is executed during this check.\n'
}

undo_failed_move() {
    local code="$1" name
    trap - ERR INT TERM HUP
    set +e
    for name in "${moved[@]}"; do
        if [[ ! -e "$HOME/$name" && ! -L "$HOME/$name" ]]; then
            cp -a -- "$saved_dir/$name" "$HOME/$name"
        fi
    done
    printf '[ERROR] Organization stopped. Originals preserved in: %s\n' "$saved_dir" >&2
    exit "$code"
}

apply_moves() {
    local name
    (( EUID != 0 )) || fail 'Run as your normal user, without sudo.'
    validate_parents "$IMPORT_ROOT"
    validate_parents "$DATA_ROOT/Installer-Backups"
    mkdir -p -- "$IMPORT_ROOT" "$DATA_ROOT/Installer-Backups"
    import_dir="$(mktemp -d "$IMPORT_ROOT/home-zsh.XXXXXX")"
    saved_dir="$(mktemp -d "$DATA_ROOT/Installer-Backups/home-zsh.XXXXXX")"
    trap 'undo_failed_move "$?"' ERR
    trap 'undo_failed_move 130' INT
    trap 'undo_failed_move 143' TERM HUP
    for name in "${candidates[@]}"; do
        [[ -f "$HOME/$name" && ! -L "$HOME/$name" ]] || return 1
        known_duplicate "$HOME/$name" || return 1
        has_reference "$name" && return 1
        cp -a -- "$HOME/$name" "$saved_dir/$name"
    done
    (cd -- "$saved_dir" && sha256sum -- "${candidates[@]}") > "$saved_dir/SHA256SUMS"
    cp -- "$saved_dir/SHA256SUMS" "$import_dir/SHA256SUMS"
    for name in "${candidates[@]}"; do
        cmp -s -- "$HOME/$name" "$saved_dir/$name"
        moved+=("$name")
        mv -- "$HOME/$name" "$import_dir/$name"
    done
    trap - ERR INT TERM HUP
    printf '\n[OK] Files moved to: %s\nSafety copy: %s\n' "$import_dir" "$saved_dir"
    printf 'To undo without overwriting existing files:\n  bash %q --restore %q\n' \
        "$CORE/tools/organize-home-zsh.sh" "$import_dir"
}

restore_batch() {
    local directory="$1" name digest line matched
    local -a restore_names=()
    (( EUID != 0 )) || fail 'Run as your normal user, without sudo.'
    directory="$(realpath -e -- "$directory")"
    [[ "${directory%/*}" == "$IMPORT_ROOT" && "${directory##*/}" == home-zsh.* ]] || \
        fail 'Choose a batch inside Config/Zsh/Imported-Home.'
    validate_parents "$directory"
    [[ -f "$directory/SHA256SUMS" && ! -L "$directory/SHA256SUMS" ]] || fail 'Manifest is missing.'
    while IFS= read -r line; do
        digest="${line%% *}"
        name="${line#*  }"
        [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail 'Invalid manifest.'
        matched=0
        for allowed in "${NAMES[@]}"; do [[ "$name" != "$allowed" ]] || matched=1; done
        (( matched )) || fail 'Name not allowed in the manifest.'
        [[ -f "$directory/$name" && ! -L "$directory/$name" ]] || fail "Invalid file: $name"
        [[ ! -e "$HOME/$name" && ! -L "$HOME/$name" ]] || fail "Destination already exists; nothing replaced: $name"
        restore_names+=("$name")
    done < "$directory/SHA256SUMS"
    (( ${#restore_names[@]} )) || fail 'Manifest is empty.'
    (cd -- "$directory" && sha256sum -c --strict SHA256SUMS) || fail 'Integrity failure.'
    for name in "${restore_names[@]}"; do
        [[ ! -e "$HOME/$name" && ! -L "$HOME/$name" ]] || fail "The destination appeared during restoration: $name"
        cp -a --no-clobber -- "$directory/$name" "$HOME/$name"
        cmp -s -- "$directory/$name" "$HOME/$name" || fail "Restoration not confirmed: $name"
    done
    printf '[OK] Files restored to Home; the batch and safety copy were retained.\n'
}

case "${1:---check}" in
    --restore) [[ $# == 2 ]] || fail 'Usage: --restore DIRECTORY'; restore_batch "$2"; exit ;;
    --check|--offer|--apply) [[ $# -le 1 ]] || fail 'Too many arguments.' ;;
    *) fail 'Usage: --check | --offer | --apply | --restore DIRECTORY' ;;
esac
scan
(( ${#candidates[@]} )) || { printf '[INFO] No candidate available.\n'; exit 0; }
[[ "${1:---check}" != --check ]] || exit 0
if [[ "$1" == --offer ]]; then
    [[ -t 0 ]] || { printf '[INFO] No interactive terminal: nothing moved.\n'; exit 0; }
    read -r -p 'Move only the candidates above, with a safety copy? [y/N]: ' answer || exit 0
    [[ "${answer,,}" == y || "${answer,,}" == yes ]] || exit 0
fi
apply_moves
