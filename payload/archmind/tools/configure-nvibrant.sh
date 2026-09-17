#!/usr/bin/env bash
# ArchMind - optional NVIDIA Digital Vibrance integration.

set -uo pipefail
IFS=$'\n\t'

readonly DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}"
readonly CONFIG_DIR="$DATA_HOME/Config/NVIDIA"
readonly CONFIG_FILE="$CONFIG_DIR/vibrance.conf"
readonly BACKUP_ROOT="$DATA_HOME/Installer-Backups/NVIDIA-Vibrance"
readonly STATE_FILE="$CONFIG_DIR/service-state.conf"
readonly USER_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly UNIT_DIR="$USER_CONFIG_HOME/systemd/user"
readonly UNIT_FILE="$UNIT_DIR/nvibrant.service"
readonly UNIT_MARKER='# Managed by ArchMind: NVIDIA Vibrance'
readonly DEFAULT_VALUE=512

info() { printf '\033[1;36m[i]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
has()  { command -v "$1" >/dev/null 2>&1; }

require_normal_user() {
    if ((EUID == 0)) && [[ "${ARCHMIND_TEST_SIMULATE:-0}" != 1 ]]; then
        fail 'Run this integration as your normal user, without sudo.'
        return 1
    fi
}

machine_id() {
    if [[ -r "${ARCHMIND_MACHINE_ID_FILE:-/etc/machine-id}" ]]; then
        tr -dc 'A-Fa-f0-9' < "${ARCHMIND_MACHINE_ID_FILE:-/etc/machine-id}" | head -c 64
    else
        printf unknown
    fi
}

valid_value() {
    [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 0 && 10#$1 <= 1023))
}

configured_value() {
    local value=""
    if [[ -r "$CONFIG_FILE" && -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]]; then
        value="$(awk -F= '$1 == "NVIBRANT_VALUE" { print $2; exit }' "$CONFIG_FILE")"
    fi
    valid_value "$value" && printf '%s\n' "$value" || printf '%s\n' "$DEFAULT_VALUE"
}

nvidia_present() {
    [[ "${ARCHMIND_TEST_NVIDIA:-}" == 1 ]] && return 0
    [[ "${ARCHMIND_TEST_NVIDIA:-}" == 0 ]] && return 1

    local vendor=""
    for vendor in /sys/class/drm/card*/device/vendor; do
        [[ -r "$vendor" ]] || continue
        grep -Fxiq '0x10de' "$vendor" && return 0
    done
    has lspci && LC_ALL=C lspci -nn 2>/dev/null | \
        grep -Eqi '(VGA|3D|Display).*NVIDIA|NVIDIA.*(VGA|3D|Display)' && return 0
    return 1
}

ensure_nvibrant() {
    has nvibrant && return 0
    nvidia_present || {
        warn 'No NVIDIA graphics device was detected; nvibrant was not installed.'
        return 1
    }

    local aur_helper=""
    if has yay; then
        aur_helper=yay
    elif has paru; then
        aur_helper=paru
    else
        warn 'nvibrant is missing and no AUR helper (yay or paru) is available.'
        return 1
    fi

    local package=""
    if "$aur_helper" -Si -- nvibrant >/dev/null 2>&1; then
        package=nvibrant
    elif "$aur_helper" -Si -- nvibrant-bin >/dev/null 2>&1; then
        package=nvibrant-bin
    else
        fail 'Neither nvibrant nor nvibrant-bin is available through the configured AUR helper.'
        return 1
    fi

    info "Installing the optional AUR package: $package"
    "$aur_helper" -S --needed -- "$package" || return 1
    has nvibrant || {
        fail 'The nvibrant executable is still unavailable after installation.'
        return 1
    }
}

unit_is_enabled() {
    has systemctl && systemctl --user is-enabled nvibrant.service >/dev/null 2>&1
}

read_state() {
    PREVIOUS_EXISTED=0
    PREVIOUS_ENABLED=0
    PREVIOUS_BACKUP=""
    STATE_MACHINE=""
    [[ -r "$STATE_FILE" && -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] || return 1

    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            MACHINE_ID) STATE_MACHINE="$value" ;;
            PREVIOUS_EXISTED) [[ "$value" == 0 || "$value" == 1 ]] && PREVIOUS_EXISTED="$value" ;;
            PREVIOUS_ENABLED) [[ "$value" == 0 || "$value" == 1 ]] && PREVIOUS_ENABLED="$value" ;;
            PREVIOUS_BACKUP) PREVIOUS_BACKUP="$value" ;;
        esac
    done < "$STATE_FILE"
    [[ "$STATE_MACHINE" == "$(machine_id)" ]]
}

safe_backup_path() {
    [[ -n "$1" && "$1" == "$BACKUP_ROOT"/* && -f "$1" && ! -L "$1" ]]
}

record_previous_service() {
    read_state && return 0

    local stamp backup="" existed=0 enabled=0
    mkdir -p -- "$CONFIG_DIR" "$BACKUP_ROOT"
    chmod 700 -- "$CONFIG_DIR" "$BACKUP_ROOT" 2>/dev/null || true
    if [[ -e "$UNIT_FILE" ]]; then
        [[ -f "$UNIT_FILE" && ! -L "$UNIT_FILE" ]] || {
            fail "Unsafe existing service refused: $UNIT_FILE"
            return 1
        }
        stamp="$(date +'%Y%m%d-%H%M%S')-$BASHPID"
        backup="$BACKUP_ROOT/nvibrant.service-before-archmind-$stamp"
        cp -a -- "$UNIT_FILE" "$backup" || return 1
        chmod 600 -- "$backup" 2>/dev/null || true
        existed=1
    fi
    unit_is_enabled && enabled=1

    umask 077
    {
        printf 'FORMAT=1\n'
        printf 'MACHINE_ID=%s\n' "$(machine_id)"
        printf 'PREVIOUS_EXISTED=%s\n' "$existed"
        printf 'PREVIOUS_ENABLED=%s\n' "$enabled"
        printf 'PREVIOUS_BACKUP=%s\n' "$backup"
    } > "$STATE_FILE"
}

write_value() {
    local value=$1 temp
    valid_value "$value" || { fail 'Vibrance must be an integer from 0 through 1023.'; return 1; }
    [[ ! -L "$CONFIG_DIR" && ! -L "$CONFIG_FILE" ]] || {
        fail 'Unsafe NVIDIA configuration path refused.'
        return 1
    }
    umask 077
    mkdir -p -- "$CONFIG_DIR"
    temp="$(mktemp "$CONFIG_DIR/.vibrance.conf.XXXXXX")" || return 1
    printf 'NVIBRANT_VALUE=%s\n' "$((10#$value))" > "$temp"
    chmod 600 -- "$temp"
    mv -- "$temp" "$CONFIG_FILE"
}

write_unit() {
    local value=$1 temp
    [[ ! -L "$UNIT_DIR" && ! -L "$UNIT_FILE" ]] || {
        fail 'Unsafe systemd user-unit path refused.'
        return 1
    }
    if [[ -f "$UNIT_FILE" ]] && ! grep -Fxq -- "$UNIT_MARKER" "$UNIT_FILE"; then
        if ! read_state || ! safe_backup_path "$PREVIOUS_BACKUP" || \
           ! cmp -s -- "$UNIT_FILE" "$PREVIOUS_BACKUP"; then
            fail 'The nvibrant service changed after its backup; refusing to overwrite it.'
            return 1
        fi
    fi

    mkdir -p -- "$UNIT_DIR"
    temp="$(mktemp "$UNIT_DIR/.nvibrant.service.XXXXXX")" || return 1
    cat > "$temp" <<EOF
$UNIT_MARKER
[Unit]
Description=Apply NVIDIA Digital Vibrance
After=graphical.target

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 5
ExecStart=/usr/bin/nvibrant $value

[Install]
WantedBy=default.target
EOF
    chmod 644 -- "$temp"
    mv -- "$temp" "$UNIT_FILE"
}

reload_and_enable() {
    has systemctl || { fail 'systemctl is unavailable.'; return 1; }
    systemctl --user daemon-reload || return 1
    systemctl --user enable --now nvibrant.service
}

apply_integration() {
    require_normal_user || return 1
    nvidia_present || {
        warn 'No NVIDIA graphics device was detected. No changes were made.'
        return 1
    }
    local value="${1:-$(configured_value)}"
    valid_value "$value" || { fail 'Vibrance must be an integer from 0 through 1023.'; return 1; }
    ensure_nvibrant || return 1
    record_previous_service || return 1
    write_value "$value" || return 1
    write_unit "$((10#$value))" || return 1
    reload_and_enable || {
        warn 'The files were created, but the user service could not be enabled.'
        return 1
    }
    ok "NVIDIA Digital Vibrance is configured at $((10#$value)) with a five-second login delay."
}

reapply_integration() {
    require_normal_user || return 1
    has nvibrant || { fail 'nvibrant is unavailable.'; return 1; }
    local value
    value="$(configured_value)"
    nvibrant "$value" || return 1
    ok "NVIDIA Digital Vibrance $value reapplied."
}

remove_integration() {
    require_normal_user || return 1
    [[ -f "$UNIT_FILE" && ! -L "$UNIT_FILE" ]] || {
        info 'The ArchMind nvibrant service is not installed.'
        return 0
    }
    grep -Fxq -- "$UNIT_MARKER" "$UNIT_FILE" || {
        fail 'The service is not managed by ArchMind; removal was refused.'
        return 1
    }

    has systemctl && systemctl --user disable --now nvibrant.service >/dev/null 2>&1 || true
    if read_state && ((PREVIOUS_EXISTED)); then
        safe_backup_path "$PREVIOUS_BACKUP" || {
            fail 'The previous service backup is unavailable; removal was stopped.'
            return 1
        }
        cp -a -- "$PREVIOUS_BACKUP" "$UNIT_FILE"
    else
        rm -f -- "$UNIT_FILE"
    fi
    if has systemctl; then
        systemctl --user daemon-reload || true
        if ((PREVIOUS_ENABLED)) && [[ -f "$UNIT_FILE" ]]; then
            systemctl --user enable --now nvibrant.service || true
        fi
    fi
    rm -f -- "$STATE_FILE"
    ok 'ArchMind nvibrant integration removed; the package was preserved.'
}

show_status() {
    local value state='not configured' device='not detected' package='missing'
    value="$(configured_value)"
    nvidia_present && device='detected'
    has nvibrant && package='installed'
    if [[ -f "$UNIT_FILE" ]] && grep -Fxq -- "$UNIT_MARKER" "$UNIT_FILE"; then
        state='configured'
        unit_is_enabled && state='enabled'
    fi
    printf 'ArchMind NVIDIA Digital Vibrance\n\n'
    printf 'NVIDIA device: %s\n' "$device"
    printf 'nvibrant:     %s\n' "$package"
    printf 'Value:        %s / 1023\n' "$value"
    printf 'User service: %s\n' "$state"
    printf 'Configuration: %s\n' "$CONFIG_FILE"
}

interactive_menu() {
    show_status
    printf '\n1) Configure with current value\n2) Set intensity\n3) Reapply now\n4) Remove integration\n0) Exit\n\nChoice: '
    local choice="" value=""
    IFS= read -r choice || return 0
    case "$choice" in
        1) apply_integration ;;
        2)
            printf 'Value from 0 through 1023: '
            IFS= read -r value || return 0
            apply_integration "$value"
            ;;
        3) reapply_integration ;;
        4)
            printf 'Type REMOVE to disable and remove the integration: '
            IFS= read -r value || return 0
            [[ "$value" == REMOVE ]] && remove_integration || info 'Cancelled.'
            ;;
        *) info 'No changes made.' ;;
    esac
}

case "${1:---menu}" in
    --apply) apply_integration "${2:-}" ;;
    --set) [[ $# == 2 ]] || { fail 'Usage: --set VALUE'; exit 2; }; apply_integration "$2" ;;
    --reapply) reapply_integration ;;
    --status) show_status ;;
    --remove) remove_integration ;;
    --menu) interactive_menu ;;
    *) fail 'Usage: --apply [VALUE] | --set VALUE | --reapply | --status | --remove | --menu'; exit 2 ;;
esac
