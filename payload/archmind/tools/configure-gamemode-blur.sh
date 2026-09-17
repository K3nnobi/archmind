#!/usr/bin/env bash
# Configure GameMode to suspend Blur My Shell while games are active.

set -uo pipefail
IFS=$'\n\t'

readonly EXTENSION_UUID="blur-my-shell@aunetx"
readonly DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly GAMEMODE_CONFIG="$CONFIG_HOME/gamemode.ini"
readonly EXTENSIONS_DIR="$DATA_HOME/Config/GameMode"
readonly EXTENSIONS_FILE="$EXTENSIONS_DIR/extensions.conf"
readonly BACKUP_DIR="$DATA_HOME/Installer-Backups"
readonly BEGIN_MARKER="; BEGIN ARCHMIND GAMEMODE BLUR"
readonly END_MARKER="; END ARCHMIND GAMEMODE BLUR"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly HOOK_SCRIPT="${ARCHMIND_GAMEMODE_HOOK:-$SCRIPT_DIR/gamemode-blur.sh}"

info() { printf '\033[1;36m[i]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }

has() { command -v "$1" >/dev/null 2>&1; }

require_normal_user() {
    if ((EUID == 0)) && [[ "${ARCHMIND_TEST_SIMULATE:-0}" != "1" ]]; then
        fail "Run this integration as your normal user, without sudo."
        return 1
    fi
}

shell_quote() {
    local value=$1
    value=${value//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

validate_targets() {
    [[ -x "$HOOK_SCRIPT" && -f "$HOOK_SCRIPT" && ! -L "$HOOK_SCRIPT" ]] || {
        fail "GameMode hook is missing or unsafe: $HOOK_SCRIPT"
        return 1
    }
    [[ ! -L "$CONFIG_HOME" && ( ! -e "$CONFIG_HOME" || -d "$CONFIG_HOME" ) ]] || {
        fail "Unsafe configuration directory refused: $CONFIG_HOME"
        return 1
    }
    [[ ! -L "$GAMEMODE_CONFIG" ]] || {
        fail "Symbolic-link configuration refused: $GAMEMODE_CONFIG"
        return 1
    }
    [[ ! -e "$GAMEMODE_CONFIG" || ( -f "$GAMEMODE_CONFIG" && -w "$GAMEMODE_CONFIG" ) ]] || {
        fail "GameMode configuration is not a writable regular file."
        return 1
    }
    [[ ! -L "$EXTENSIONS_DIR" && ! -L "$EXTENSIONS_FILE" ]] || {
        fail "Unsafe ArchMind GameMode configuration path refused."
        return 1
    }
}

install_dependencies() {
    local -a missing=()
    has pacman || {
        warn "Pacman is unavailable; GameMode packages were not checked."
        return 1
    }
    pacman -Q gamemode >/dev/null 2>&1 || missing+=(gamemode)
    pacman -Q lib32-gamemode >/dev/null 2>&1 || missing+=(lib32-gamemode)
    ((${#missing[@]})) || return 0

    has sudo || {
        warn "Missing packages: ${missing[*]}. sudo is unavailable."
        return 1
    }
    info "Installing required GameMode packages: ${missing[*]}"
    if ! sudo pacman -S --needed -- "${missing[@]}"; then
        warn "GameMode packages could not be installed. Ensure multilib is enabled."
        return 1
    fi
}

ensure_extension_list() {
    umask 077
    mkdir -p -- "$EXTENSIONS_DIR"
    chmod 700 -- "$EXTENSIONS_DIR" 2>/dev/null || true
    if [[ ! -e "$EXTENSIONS_FILE" ]]; then
        printf '%s\n' "$EXTENSION_UUID" > "$EXTENSIONS_FILE"
        chmod 600 -- "$EXTENSIONS_FILE" 2>/dev/null || true
    elif ! grep -Fxq -- "$EXTENSION_UUID" "$EXTENSIONS_FILE"; then
        printf '%s\n' "$EXTENSION_UUID" >> "$EXTENSIONS_FILE"
    fi
}

strip_managed_block() {
    local source=$1 destination=$2
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
        $0 == begin { inside=1; next }
        $0 == end   { inside=0; next }
        !inside {
            if ($0 ~ /^[[:space:]]*(start|end)[[:space:]]*=/ &&
                $0 ~ /\/\.local\/bin\/gamemode-blur[[:space:]]+(start|end)[[:space:]]*$/) {
                next
            }
            lines[++count]=$0
        }
        END {
            while (count > 0 && lines[count] ~ /^[[:space:]]*$/) count--
            for (i=1; i<=count; i++) print lines[i]
        }
    ' "$source" > "$destination"
}

write_config() {
    local temp quoted_hook stamp
    umask 077
    mkdir -p -- "$CONFIG_HOME" "$BACKUP_DIR"
    chmod 700 -- "$BACKUP_DIR" 2>/dev/null || true
    temp="$(mktemp "$CONFIG_HOME/.gamemode.ini.XXXXXX")" || return 1

    if [[ -f "$GAMEMODE_CONFIG" ]]; then
        strip_managed_block "$GAMEMODE_CONFIG" "$temp" || {
            rm -f -- "$temp"
            return 1
        }
        chmod --reference="$GAMEMODE_CONFIG" "$temp" 2>/dev/null || chmod 600 -- "$temp"
    else
        : > "$temp"
        chmod 600 -- "$temp"
    fi

    quoted_hook="$(shell_quote "$HOOK_SCRIPT")"
    {
        printf '\n%s\n' "$BEGIN_MARKER"
        printf '%s\n' '[custom]'
        printf 'start=%s start\n' "$quoted_hook"
        printf 'end=%s end\n' "$quoted_hook"
        printf '%s\n' "$END_MARKER"
    } >> "$temp"

    if [[ -f "$GAMEMODE_CONFIG" ]] && cmp -s -- "$temp" "$GAMEMODE_CONFIG"; then
        rm -f -- "$temp"
        return 0
    fi
    if [[ -f "$GAMEMODE_CONFIG" ]]; then
        stamp="$(date +'%Y%m%d-%H%M%S')-$BASHPID"
        cp -a -- "$GAMEMODE_CONFIG" "$BACKUP_DIR/gamemode.ini-before-archmind-$stamp"
    fi
    mv -- "$temp" "$GAMEMODE_CONFIG"
}

remove_config_block() {
    [[ -f "$GAMEMODE_CONFIG" ]] || return 0
    local temp stamp
    temp="$(mktemp "$CONFIG_HOME/.gamemode.ini.XXXXXX")" || return 1
    strip_managed_block "$GAMEMODE_CONFIG" "$temp" || {
        rm -f -- "$temp"
        return 1
    }
    if cmp -s -- "$temp" "$GAMEMODE_CONFIG"; then
        rm -f -- "$temp"
        return 0
    fi
    mkdir -p -- "$BACKUP_DIR"
    stamp="$(date +'%Y%m%d-%H%M%S')-$BASHPID"
    cp -a -- "$GAMEMODE_CONFIG" "$BACKUP_DIR/gamemode.ini-before-remove-$stamp"
    chmod --reference="$GAMEMODE_CONFIG" "$temp" 2>/dev/null || chmod 600 -- "$temp"
    mv -- "$temp" "$GAMEMODE_CONFIG"
}

extension_installed() {
    has gnome-extensions && \
        gnome-extensions list 2>/dev/null | grep -Fxq -- "$EXTENSION_UUID"
}

extension_enabled() {
    has gnome-extensions && \
        gnome-extensions list --enabled 2>/dev/null | grep -Fxq -- "$EXTENSION_UUID"
}

integration_configured() {
    [[ -f "$GAMEMODE_CONFIG" ]] && \
        grep -Fxq -- "$BEGIN_MARKER" "$GAMEMODE_CONFIG" && \
        grep -Fq -- "$(shell_quote "$HOOK_SCRIPT") start" "$GAMEMODE_CONFIG" && \
        grep -Fq -- "$(shell_quote "$HOOK_SCRIPT") end" "$GAMEMODE_CONFIG"
}

show_status() {
    local package_state='unavailable' lib32_state='unavailable'
    if has pacman; then
        package_state="$(pacman -Q gamemode >/dev/null 2>&1 && printf installed || printf missing)"
        lib32_state="$(pacman -Q lib32-gamemode >/dev/null 2>&1 && printf installed || printf missing)"
    fi
    printf 'ArchMind GameMode + Blur My Shell\n\n'
    printf 'GameMode package:        %s\n' "$package_state"
    printf '32-bit GameMode library: %s\n' "$lib32_state"
    printf 'Blur My Shell:          %s\n' "$(extension_installed && printf installed || printf missing)"
    printf 'Blur current state:     %s\n' "$(extension_enabled && printf enabled || printf disabled)"
    printf 'Managed hooks:          %s\n' "$(integration_configured && printf configured || printf not-configured)"
    printf 'GameMode config:        %s\n' "$GAMEMODE_CONFIG"
    printf 'Extension policy:       %s\n' "$EXTENSIONS_FILE"
}

apply_integration() {
    require_normal_user || return 1
    validate_targets || return 1
    local failed=0

    install_dependencies || failed=1
    if ! has gnome-extensions; then
        warn "gnome-extensions is unavailable; hooks will be configured for a future GNOME session."
    elif ! extension_installed; then
        warn "Blur My Shell is not installed; hooks will remain ready if it is installed later."
    fi

    ensure_extension_list || return 1
    write_config || {
        fail "Could not update $GAMEMODE_CONFIG"
        return 1
    }

    ok "GameMode hooks configured without replacing existing custom scripts."
    printf 'Steam launch option: gamemoderun %%command%%\n'
    printf 'Test command: %s --test\n' "${0##*/}"
    ((failed == 0))
}

test_integration() {
    require_normal_user || return 1
    integration_configured || {
        fail "The managed GameMode hooks are not configured. Run --apply first."
        return 1
    }
    has gamemoderun || { fail "gamemoderun is unavailable."; return 1; }
    extension_installed || { fail "Blur My Shell is not installed in this GNOME session."; return 1; }
    extension_enabled || {
        fail "Enable Blur My Shell before running the automatic test."
        return 1
    }

    local status_output="" test_pid=0 disabled=0 restored=0 i
    if has gamemoded; then
        status_output="$(LC_ALL=C gamemoded -s 2>/dev/null || true)"
        if grep -Fqi 'gamemode is active' <<< "$status_output"; then
            fail "GameMode is already active. Close games before testing."
            return 1
        fi
    fi

    # GameMode monitors configuration changes, but an explicit test should be
    # deterministic even on older daemon builds. It is safe to restart here
    # because the active-client guard above has already passed.
    if has systemctl && systemctl --user cat gamemoded.service >/dev/null 2>&1; then
        systemctl --user restart gamemoded.service >/dev/null 2>&1 || true
    else
        sleep 6
    fi

    info "Starting a four-second GameMode test..."
    gamemoderun sleep 4 &
    test_pid=$!
    for ((i=0; i<30; i++)); do
        if ! extension_enabled; then disabled=1; break; fi
        sleep 0.1
    done
    wait "$test_pid" || {
        "$HOOK_SCRIPT" recover >/dev/null 2>&1 || true
        fail "gamemoderun returned an error."
        return 1
    }
    for ((i=0; i<30; i++)); do
        if extension_enabled; then restored=1; break; fi
        sleep 0.1
    done
    if ((disabled && restored)); then
        ok "Validated: Blur was disabled during GameMode and restored afterward."
        return 0
    fi
    "$HOOK_SCRIPT" recover >/dev/null 2>&1 || true
    ((disabled)) || fail "Blur My Shell did not disable while GameMode was active."
    ((restored)) || fail "Blur My Shell was not restored after GameMode ended."
    return 1
}

remove_integration() {
    require_normal_user || return 1
    validate_targets || return 1
    "$HOOK_SCRIPT" recover || warn "No pending extension state could be restored."
    remove_config_block || return 1
    ok "Managed hooks removed. GameMode packages and other custom hooks were preserved."
}

interactive_menu() {
    show_status
    printf '\n1) Configure or repair\n2) Run four-second test\n3) Remove integration\n0) Exit\n\nChoice: '
    local choice=""
    IFS= read -r choice || return 0
    case "$choice" in
        1) apply_integration ;;
        2) test_integration ;;
        3)
            printf 'Type REMOVE to remove only the managed hooks: '
            IFS= read -r choice || return 0
            [[ "$choice" == "REMOVE" ]] && remove_integration || info "Cancelled."
            ;;
        *) info "No changes made." ;;
    esac
}

case "${1:---menu}" in
    --apply) apply_integration ;;
    --check) show_status; integration_configured ;;
    --test) test_integration ;;
    --remove) remove_integration ;;
    --menu) interactive_menu ;;
    *)
        printf 'Usage: %s [--apply|--check|--test|--remove|--menu]\n' "${0##*/}" >&2
        exit 2
        ;;
esac
