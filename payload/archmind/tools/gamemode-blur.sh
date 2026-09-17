#!/usr/bin/env bash
# ArchMind - GameMode hook for temporarily disabling GNOME extensions.

set -uo pipefail
IFS=$'\n\t'

readonly DEFAULT_EXTENSION="blur-my-shell@aunetx"
readonly DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}"
readonly EXTENSIONS_FILE="${ARCHMIND_GAMEMODE_EXTENSIONS_FILE:-$DATA_HOME/Config/GameMode/extensions.conf}"
readonly RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
readonly STATE_DIR="$RUNTIME_BASE/archmind-gamemode"
readonly STATE_FILE="$STATE_DIR/extensions-were-enabled"
readonly LOCK_FILE="$STATE_DIR/lock"

log() {
    if [[ "${ARCHMIND_GAMEMODE_QUIET:-0}" != "1" ]]; then
        printf 'ArchMind GameMode: %s\n' "$*" >&2
    fi
}

valid_extension_uuid() {
    [[ "$1" =~ ^[A-Za-z0-9._+@-]+$ ]]
}

load_extensions() {
    local line=""
    EXTENSIONS=()

    if [[ -r "$EXTENSIONS_FILE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -n "$line" ]] || continue
            if valid_extension_uuid "$line"; then
                EXTENSIONS+=("$line")
            else
                log "ignored invalid extension UUID: $line"
            fi
        done < "$EXTENSIONS_FILE"
    fi

    ((${#EXTENSIONS[@]})) || EXTENSIONS=("$DEFAULT_EXTENSION")
}

prepare_runtime() {
    [[ -d "$RUNTIME_BASE" && -O "$RUNTIME_BASE" ]] || {
        log "secure user runtime directory is unavailable: $RUNTIME_BASE"
        return 1
    }
    mkdir -p -m 700 -- "$STATE_DIR" || return 1
    [[ -d "$STATE_DIR" && -O "$STATE_DIR" && ! -L "$STATE_DIR" ]] || {
        log "unsafe state directory refused: $STATE_DIR"
        return 1
    }
    chmod 700 -- "$STATE_DIR" 2>/dev/null || true
}

with_lock() {
    command -v flock >/dev/null 2>&1 || {
        log "flock is required (Arch package: util-linux)"
        return 1
    }
    prepare_runtime || return 1
    exec 9>"$LOCK_FILE" || return 1
    flock -x 9 || return 1
}

enabled_extensions() {
    gnome-extensions list --enabled 2>/dev/null
}

installed_extensions() {
    gnome-extensions list 2>/dev/null
}

hook_start() {
    command -v gnome-extensions >/dev/null 2>&1 || {
        log "gnome-extensions is unavailable; nothing changed"
        return 0
    }
    with_lock || return 1

    # GameMode normally calls the hook once for its first client. This guard
    # also makes direct or duplicate calls safe: they cannot erase the state
    # needed to restore extensions when the final client exits.
    if [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]]; then
        return 0
    fi
    [[ ! -e "$STATE_FILE" && ! -L "$STATE_FILE" ]] || {
        log "unsafe state file refused: $STATE_FILE"
        return 1
    }

    local installed enabled extension temp failed=0
    installed="$(installed_extensions)" || {
        log "could not query GNOME extensions"
        return 1
    }
    enabled="$(enabled_extensions)" || {
        log "could not query enabled GNOME extensions"
        return 1
    }

    temp="$(mktemp "$STATE_DIR/.extensions.XXXXXX")" || return 1
    chmod 600 -- "$temp" 2>/dev/null || true

    load_extensions
    for extension in "${EXTENSIONS[@]}"; do
        grep -Fxq -- "$extension" <<< "$installed" || continue
        grep -Fxq -- "$extension" <<< "$enabled" || continue
        if gnome-extensions disable "$extension" >/dev/null 2>&1; then
            printf '%s\n' "$extension" >> "$temp"
            log "disabled $extension"
        else
            log "failed to disable $extension"
            failed=1
        fi
    done

    mv -- "$temp" "$STATE_FILE" || {
        rm -f -- "$temp"
        return 1
    }
    return "$failed"
}

hook_end() {
    command -v gnome-extensions >/dev/null 2>&1 || {
        log "gnome-extensions is unavailable; restoration is pending"
        return 1
    }
    with_lock || return 1
    [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] || return 0

    local installed extension pending failed=0
    installed="$(installed_extensions)" || {
        log "could not query GNOME extensions; restoration is pending"
        return 1
    }
    pending="$(mktemp "$STATE_DIR/.pending.XXXXXX")" || return 1
    chmod 600 -- "$pending" 2>/dev/null || true

    while IFS= read -r extension || [[ -n "$extension" ]]; do
        [[ -n "$extension" ]] || continue
        valid_extension_uuid "$extension" || continue
        grep -Fxq -- "$extension" <<< "$installed" || continue
        if gnome-extensions enable "$extension" >/dev/null 2>&1; then
            log "restored $extension"
        else
            printf '%s\n' "$extension" >> "$pending"
            log "failed to restore $extension; state preserved"
            failed=1
        fi
    done < "$STATE_FILE"

    if ((failed)); then
        mv -- "$pending" "$STATE_FILE"
    else
        rm -f -- "$pending" "$STATE_FILE"
    fi
    return "$failed"
}

hook_status() {
    local installed="" enabled="" extension state="not installed"
    command -v gnome-extensions >/dev/null 2>&1 || {
        printf 'GNOME extensions command: unavailable\n'
        return 1
    }
    installed="$(installed_extensions)" || true
    enabled="$(enabled_extensions)" || true
    load_extensions

    printf 'GameMode extension policy:\n'
    for extension in "${EXTENSIONS[@]}"; do
        state="not installed"
        if grep -Fxq -- "$extension" <<< "$installed"; then
            state="disabled"
            grep -Fxq -- "$extension" <<< "$enabled" && state="enabled"
        fi
        printf '  %s: %s\n' "$extension" "$state"
    done
    if [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]]; then
        printf 'Restoration state: present\n'
    else
        printf 'Restoration state: absent\n'
    fi
}

case "${1:-}" in
    start) hook_start ;;
    end|recover) hook_end ;;
    status) hook_status ;;
    *)
        printf 'Usage: %s {start|end|recover|status}\n' "${0##*/}" >&2
        exit 2
        ;;
esac

