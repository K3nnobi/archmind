#!/usr/bin/env bash
# ArchMind - reversible Plymouth spinner + quiet GRUB patch.

set -uo pipefail
IFS=$'\n\t'

readonly DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}"
readonly PATCH_CONFIG_DIR="$DATA_HOME/Config/Patches/Plymouth"
readonly STATE_FILE="$PATCH_CONFIG_DIR/state.conf"
readonly BACKUP_ROOT="$DATA_HOME/Installer-Backups/Plymouth"
readonly TEMP_ROOT="$DATA_HOME/Temp"
readonly LOCK_FILE="$TEMP_ROOT/plymouth-patch.lock"
readonly SYSTEM_ROOT="${ARCHMIND_PLYMOUTH_ROOT:-}"
readonly TRANSFORMER="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/plymouth-transform.py"

readonly PLYMOUTH_CONF="$SYSTEM_ROOT/etc/plymouth/plymouthd.conf"
readonly MKINITCPIO_CONF="$SYSTEM_ROOT/etc/mkinitcpio.conf"
readonly GRUB_DEFAULT="$SYSTEM_ROOT/etc/default/grub"
readonly GRUB_SCRIPT="$SYSTEM_ROOT/etc/grub.d/10_linux"
readonly GRUB_CFG="$SYSTEM_ROOT/boot/grub/grub.cfg"
readonly MACHINE_ID_FILE="$SYSTEM_ROOT/etc/machine-id"

active_stage=""
active_snapshot=""
rollback_needed=0

info() { printf '\033[1;36m[i]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
has()  { command -v "$1" >/dev/null 2>&1; }

cleanup_stage() {
    case "$active_stage" in
        "$TEMP_ROOT"/plymouth-apply.*|"$TEMP_ROOT"/plymouth-remove.*)
            [[ -d "$active_stage" && ! -L "$active_stage" ]] && rm -rf -- "$active_stage"
            ;;
    esac
    active_stage=""
}

finish() {
    local status=$?
    trap - EXIT
    if ((rollback_needed)); then
        fail 'The Plymouth transaction was interrupted; restoring its snapshot.'
        if restore_snapshot "$active_snapshot"; then
            rebuild_boot >/dev/null 2>&1 || \
                warn "Files were restored, but boot regeneration must be run manually. Snapshot: $active_snapshot"
        else
            warn "Automatic restoration was incomplete. Emergency snapshot: $active_snapshot"
        fi
        ((status == 0)) && status=1
    fi
    cleanup_stage
    exit "$status"
}
trap finish EXIT

require_normal_user() {
    if ((EUID == 0)) && [[ "${ARCHMIND_TEST_SIMULATE:-0}" != 1 ]]; then
        fail 'Run this patch as your normal user, without sudo.'
        return 1
    fi
}

run_privileged() {
    if [[ "${ARCHMIND_TEST_SIMULATE:-0}" == 1 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

machine_id() {
    if [[ -r "$MACHINE_ID_FILE" ]]; then
        tr -dc 'A-Fa-f0-9' < "$MACHINE_ID_FILE" | head -c 64
    else
        printf unknown
    fi
}

read_state() {
    STATE_MACHINE=""
    THEME_PREVIOUS="__ABSENT__"
    MKINITCPIO_ADDED=0
    PLYMOUTH_HOOK_PREVIOUS_INDEX=-1
    QUIET_ADDED=0
    SPLASH_ADDED=0
    [[ -r "$STATE_FILE" && -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] || return 1

    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            MACHINE_ID) STATE_MACHINE="$value" ;;
            THEME_PREVIOUS)
                [[ "$value" == __ABSENT__ || "$value" =~ ^[A-Za-z0-9_.+-]+$ ]] && THEME_PREVIOUS="$value"
                ;;
            MKINITCPIO_ADDED) [[ "$value" == 0 || "$value" == 1 ]] && MKINITCPIO_ADDED="$value" ;;
            PLYMOUTH_HOOK_PREVIOUS_INDEX)
                [[ "$value" =~ ^-?[0-9]+$ ]] && PLYMOUTH_HOOK_PREVIOUS_INDEX="$value"
                ;;
            QUIET_ADDED) [[ "$value" == 0 || "$value" == 1 ]] && QUIET_ADDED="$value" ;;
            SPLASH_ADDED) [[ "$value" == 0 || "$value" == 1 ]] && SPLASH_ADDED="$value" ;;
        esac
    done < "$STATE_FILE"
    [[ "$STATE_MACHINE" == "$(machine_id)" ]]
}

write_state() {
    local destination=$1
    umask 077
    {
        printf 'FORMAT=1\n'
        printf 'MACHINE_ID=%s\n' "$(machine_id)"
        printf 'THEME_PREVIOUS=%s\n' "$THEME_PREVIOUS"
        printf 'MKINITCPIO_ADDED=%s\n' "$MKINITCPIO_ADDED"
        printf 'PLYMOUTH_HOOK_PREVIOUS_INDEX=%s\n' "$PLYMOUTH_HOOK_PREVIOUS_INDEX"
        printf 'QUIET_ADDED=%s\n' "$QUIET_ADDED"
        printf 'SPLASH_ADDED=%s\n' "$SPLASH_ADDED"
    } > "$destination"
}

validate_environment() {
    require_normal_user || return 1
    has python3 || { fail 'Python 3 is required by this patch.'; return 1; }
    has flock || { fail 'flock is required (util-linux).'; return 1; }
    [[ -x "$TRANSFORMER" && -f "$TRANSFORMER" && ! -L "$TRANSFORMER" ]] || {
        fail "Plymouth transformer is missing or unsafe: $TRANSFORMER"
        return 1
    }
    if [[ "${ARCHMIND_TEST_SIMULATE:-0}" != 1 ]]; then
        has sudo || { fail 'sudo is required for system boot files.'; return 1; }
        has pacman && pacman -Q plymouth >/dev/null 2>&1 || {
            fail 'Plymouth is not installed. Install the Base profile or: sudo pacman -S plymouth'
            return 1
        }
        has plymouth-set-default-theme || { fail 'plymouth-set-default-theme is unavailable.'; return 1; }
        plymouth-set-default-theme -l 2>/dev/null | grep -Fxq spinner || {
            fail 'The standard Plymouth spinner theme is unavailable.'
            return 1
        }
        has mkinitcpio || { fail 'mkinitcpio is unavailable.'; return 1; }
        has grub-mkconfig || { fail 'grub-mkconfig is unavailable; only GRUB is supported.'; return 1; }
    fi
    local target
    for target in "$PLYMOUTH_CONF" "$MKINITCPIO_CONF" "$GRUB_DEFAULT" "$GRUB_SCRIPT"; do
        [[ -f "$target" && ! -L "$target" ]] || {
            fail "Required regular file is missing or unsafe: $target"
            return 1
        }
    done
    [[ -d "$(dirname -- "$GRUB_CFG")" ]] || {
        fail "GRUB output directory is missing: $(dirname -- "$GRUB_CFG")"
        return 1
    }
    [[ ! -L "$PATCH_CONFIG_DIR" && ! -L "$STATE_FILE" && ! -L "$BACKUP_ROOT" ]] || {
        fail 'Unsafe ArchMind patch state path refused.'
        return 1
    }
}

lock_patch() {
    mkdir -p -- "$TEMP_ROOT"
    exec 9>"$LOCK_FILE" || return 1
    flock -x 9
}

make_snapshot() {
    local reason=$1 stamp snapshot target name
    stamp="$(date +'%Y%m%d-%H%M%S')-$BASHPID"
    snapshot="$BACKUP_ROOT/${reason}-${stamp}"
    mkdir -p -- "$snapshot"
    chmod 700 -- "$BACKUP_ROOT" "$snapshot" 2>/dev/null || true
    for target in "$PLYMOUTH_CONF" "$MKINITCPIO_CONF" "$GRUB_DEFAULT" "$GRUB_SCRIPT"; do
        name="$(sed 's#^/##; s#/#__#g' <<< "${target#"$SYSTEM_ROOT"}")"
        run_privileged cp -a -- "$target" "$snapshot/$name" || return 1
    done
    printf '%s\n' "$snapshot"
}

install_staged_file() {
    local staged=$1 target=$2 mode
    cmp -s -- "$staged" "$target" && return 0
    mode="$(stat -c '%a' -- "$target")" || return 1
    run_privileged install -o root -g root -m "$mode" -- "$staged" "$target"
}

restore_snapshot() {
    local snapshot=$1 target name failed=0
    [[ "$snapshot" == "$BACKUP_ROOT"/* && -d "$snapshot" && ! -L "$snapshot" ]] || return 1
    for target in "$PLYMOUTH_CONF" "$MKINITCPIO_CONF" "$GRUB_DEFAULT" "$GRUB_SCRIPT"; do
        name="$(sed 's#^/##; s#/#__#g' <<< "${target#"$SYSTEM_ROOT"}")"
        [[ -f "$snapshot/$name" && ! -L "$snapshot/$name" ]] || { failed=1; continue; }
        run_privileged cp -a -- "$snapshot/$name" "$target" || failed=1
    done
    return "$failed"
}

rebuild_boot() {
    if [[ "${ARCHMIND_TEST_SIMULATE:-0}" == 1 ]]; then
        run_privileged mkinitcpio -P || return 1
        run_privileged grub-mkconfig -o "$GRUB_CFG"
    else
        sudo mkinitcpio -P || return 1
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
}

metadata_value() {
    local key=$1 data=$2 value
    value="$(awk -F= -v wanted="$key" '$1 == wanted { print $2; exit }' <<< "$data")"
    printf '%s\n' "$value"
}

apply_patch_files() {
    validate_environment || return 1
    lock_patch || return 1

    local stage snapshot metadata_theme metadata_hooks metadata_cmd state_temp
    local had_state=0 changed=0
    stage="$(mktemp -d "$TEMP_ROOT/plymouth-apply.XXXXXX")" || return 1
    active_stage="$stage"
    state_temp="$stage/state.conf"

    if read_state; then
        had_state=1
    elif [[ -f "$STATE_FILE" ]]; then
        warn 'A Plymouth state from another machine was ignored and will be replaced.'
    fi

    metadata_theme="$(python3 -B "$TRANSFORMER" apply theme "$PLYMOUTH_CONF" "$stage/plymouthd.conf")" || return 1
    metadata_hooks="$(python3 -B "$TRANSFORMER" apply hooks "$MKINITCPIO_CONF" "$stage/mkinitcpio.conf")" || return 1
    metadata_cmd="$(python3 -B "$TRANSFORMER" apply cmdline "$GRUB_DEFAULT" "$stage/grub-default")" || return 1
    python3 -B "$TRANSFORMER" apply grub-script "$GRUB_SCRIPT" "$stage/10_linux" || return 1

    if ((had_state == 0)); then
        THEME_PREVIOUS="$(metadata_value THEME_PREVIOUS "$metadata_theme")"
        MKINITCPIO_ADDED="$(metadata_value MKINITCPIO_ADDED "$metadata_hooks")"
        PLYMOUTH_HOOK_PREVIOUS_INDEX="$(metadata_value PLYMOUTH_HOOK_PREVIOUS_INDEX "$metadata_hooks")"
        QUIET_ADDED="$(metadata_value QUIET_ADDED "$metadata_cmd")"
        SPLASH_ADDED="$(metadata_value SPLASH_ADDED "$metadata_cmd")"
    fi
    write_state "$state_temp" || return 1

    cmp -s "$stage/plymouthd.conf" "$PLYMOUTH_CONF" || changed=1
    cmp -s "$stage/mkinitcpio.conf" "$MKINITCPIO_CONF" || changed=1
    cmp -s "$stage/grub-default" "$GRUB_DEFAULT" || changed=1
    cmp -s "$stage/10_linux" "$GRUB_SCRIPT" || changed=1

    if ((changed)); then
        snapshot="$(make_snapshot apply)" || return 1
        active_snapshot="$snapshot"
        rollback_needed=1
        install_staged_file "$stage/plymouthd.conf" "$PLYMOUTH_CONF" || return 1
        install_staged_file "$stage/mkinitcpio.conf" "$MKINITCPIO_CONF" || return 1
        install_staged_file "$stage/grub-default" "$GRUB_DEFAULT" || return 1
        install_staged_file "$stage/10_linux" "$GRUB_SCRIPT" || return 1
        info 'Rebuilding all installed initramfs presets and GRUB configuration...'
        if ! rebuild_boot; then
            fail 'Boot rebuild failed; the exit guard will restore the pre-patch snapshot.'
            return 1
        fi
        rollback_needed=0
        active_snapshot=""
    fi

    mkdir -p -- "$PATCH_CONFIG_DIR"
    chmod 700 -- "$PATCH_CONFIG_DIR" 2>/dev/null || true
    mv -- "$state_temp" "$STATE_FILE"
    chmod 600 -- "$STATE_FILE" 2>/dev/null || true
    ok 'Plymouth spinner patch applied. Reboot is required to validate the visual result.'
}

remove_patch_files() {
    validate_environment || return 1
    lock_patch || return 1
    read_state || {
        fail 'No removable Plymouth state exists for this machine.'
        return 1
    }

    local stage snapshot changed=0
    local -a cmdline_remove_args=()
    stage="$(mktemp -d "$TEMP_ROOT/plymouth-remove.XXXXXX")" || return 1
    active_stage="$stage"
    python3 -B "$TRANSFORMER" remove theme "$PLYMOUTH_CONF" "$stage/plymouthd.conf" \
        --previous-theme "$THEME_PREVIOUS" || return 1
    python3 -B "$TRANSFORMER" remove hooks "$MKINITCPIO_CONF" "$stage/mkinitcpio.conf" \
        --previous-hook-index "$PLYMOUTH_HOOK_PREVIOUS_INDEX" || return 1
    [[ "$QUIET_ADDED" == 1 ]] && cmdline_remove_args+=(--remove-quiet)
    [[ "$SPLASH_ADDED" == 1 ]] && cmdline_remove_args+=(--remove-splash)
    python3 -B "$TRANSFORMER" remove cmdline "$GRUB_DEFAULT" "$stage/grub-default" \
        "${cmdline_remove_args[@]}" || return 1
    python3 -B "$TRANSFORMER" remove grub-script "$GRUB_SCRIPT" "$stage/10_linux" || return 1

    cmp -s "$stage/plymouthd.conf" "$PLYMOUTH_CONF" || changed=1
    cmp -s "$stage/mkinitcpio.conf" "$MKINITCPIO_CONF" || changed=1
    cmp -s "$stage/grub-default" "$GRUB_DEFAULT" || changed=1
    cmp -s "$stage/10_linux" "$GRUB_SCRIPT" || changed=1
    if ((changed)); then
        snapshot="$(make_snapshot remove)" || return 1
        active_snapshot="$snapshot"
        rollback_needed=1
        install_staged_file "$stage/plymouthd.conf" "$PLYMOUTH_CONF" || return 1
        install_staged_file "$stage/mkinitcpio.conf" "$MKINITCPIO_CONF" || return 1
        install_staged_file "$stage/grub-default" "$GRUB_DEFAULT" || return 1
        install_staged_file "$stage/10_linux" "$GRUB_SCRIPT" || return 1
        info 'Rebuilding initramfs and GRUB after removal...'
        if ! rebuild_boot; then
            fail 'Boot rebuild failed; the exit guard will restore the state from before removal.'
            return 1
        fi
        rollback_needed=0
        active_snapshot=""
    fi
    rm -f -- "$STATE_FILE"
    ok 'Plymouth patch removed. The Plymouth package was preserved.'
}

status_value() {
    "$@" >/dev/null 2>&1 && printf OK || printf 'NEEDS ATTENTION'
}

show_status() {
    local package_status='missing' state_status='absent'
    has pacman && pacman -Q plymouth >/dev/null 2>&1 && package_status='installed'
    if read_state; then
        state_status='current machine'
    elif [[ -f "$STATE_FILE" ]]; then
        state_status='different machine or invalid'
    fi
    printf 'ArchMind Plymouth / Boot Visual\n\n'
    printf 'Plymouth package:      %s\n' "$package_status"
    printf 'Theme spinner:         %s\n' "$(status_value python3 -B "$TRANSFORMER" audit theme "$PLYMOUTH_CONF")"
    printf 'mkinitcpio hook:       %s\n' "$(status_value python3 -B "$TRANSFORMER" audit hooks "$MKINITCPIO_CONF")"
    printf 'quiet + splash:        %s\n' "$(status_value python3 -B "$TRANSFORMER" audit cmdline "$GRUB_DEFAULT")"
    printf 'GRUB Linux message:    %s\n' "$(grep -Eq '# ARCHMIND_PLYMOUTH_(HIDE_LINUX|PREHIDDEN_LINUX):' "$GRUB_SCRIPT" && printf HIDDEN || printf VISIBLE)"
    printf 'GRUB initrd message:   %s\n' "$(grep -Eq '# ARCHMIND_PLYMOUTH_(HIDE_INITRD|PREHIDDEN_INITRD):' "$GRUB_SCRIPT" && printf HIDDEN || printf VISIBLE)"
    printf 'Reversible state:      %s\n' "$state_status"
}

check_status() {
    python3 -B "$TRANSFORMER" audit theme "$PLYMOUTH_CONF" &&
        python3 -B "$TRANSFORMER" audit hooks "$MKINITCPIO_CONF" &&
        python3 -B "$TRANSFORMER" audit cmdline "$GRUB_DEFAULT" &&
        python3 -B "$TRANSFORMER" audit grub-script "$GRUB_SCRIPT"
}

interactive_menu() {
    show_status
    printf '\n1) Apply or reapply patch\n2) Remove patch\n3) Refresh status\n0) Exit\n\nChoice: '
    local choice="" confirmation=""
    IFS= read -r choice || return 0
    case "$choice" in
        1)
            warn 'This changes initramfs and GRUB generator files.'
            printf 'Type PLYMOUTH to continue: '
            IFS= read -r confirmation || return 0
            if [[ "$confirmation" == PLYMOUTH ]]; then
                apply_patch_files
            else
                info 'Cancelled.'
            fi
            ;;
        2)
            printf 'Type REMOVE to revert only changes recorded for this machine: '
            IFS= read -r confirmation || return 0
            if [[ "$confirmation" == REMOVE ]]; then
                remove_patch_files
            else
                info 'Cancelled.'
            fi
            ;;
        3) show_status ;;
        *) info 'No changes made.' ;;
    esac
}

case "${1:---menu}" in
    --apply|--reapply) apply_patch_files ;;
    --remove) remove_patch_files ;;
    --status) show_status ;;
    --check) show_status; check_status ;;
    --menu) interactive_menu ;;
    *) fail 'Usage: --apply | --reapply | --remove | --status | --check | --menu'; exit 2 ;;
esac
