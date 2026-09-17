#!/usr/bin/env bash
# Optional, reversible Caps Lock No Delay integration using keyd.

set -Eeuo pipefail
IFS=$'\n\t'

readonly MARKER="ARCHMIND_CAPSLOCK_NODELAY"
readonly DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}"
readonly BACKUP_ROOT="$DATA_HOME/Installer-Backups/Caps-Lock-No-Delay"
readonly STATE_ROOT="$DATA_HOME/Config/Caps-Lock-No-Delay"
readonly STATE_FILE="$STATE_ROOT/state.conf"
readonly CONFIG="${ARCHMIND_KEYD_CONFIG:-/etc/keyd/default.conf}"

ACTION="menu"
ASSUME_YES=0
TEMP_FILE=""

info() { printf '\033[1;36m[i]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
has()  { command -v "$1" >/dev/null 2>&1; }

cleanup() {
    [[ -z "$TEMP_FILE" ]] || rm -f -- "$TEMP_FILE"
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
ArchMind Caps Lock No Delay

Usage:
  configure-capslock-nodelay.sh --menu
  configure-capslock-nodelay.sh --status
  configure-capslock-nodelay.sh --apply [--yes]
  configure-capslock-nodelay.sh --remove [--yes]

The patch installs keyd and safely adds capslock = macro(capslock). Existing
Caps Lock remappings are never overwritten. Removing the patch keeps the keyd
package installed because other user mappings may depend on it.
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --menu) ACTION="menu" ;;
            --status) ACTION="status" ;;
            --apply) ACTION="apply" ;;
            --remove) ACTION="remove" ;;
            --yes|-y) ASSUME_YES=1 ;;
            --help|-h) usage; exit 0 ;;
            *) fail "Unknown option: $1"; usage; return 2 ;;
        esac
        shift
    done
}

require_normal_user() {
    if ((EUID == 0)) && [[ "${ARCHMIND_TEST_SIMULATE:-0}" != "1" ]]; then
        fail "Run this patch as your normal user, without sudo."
        return 1
    fi
}

run_root() {
    if [[ "${ARCHMIND_TEST_SIMULATE:-0}" == "1" ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

confirm() {
    local prompt="$1" answer=""
    ((ASSUME_YES)) && return 0
    [[ -t 0 ]] || { fail "Confirmation requires an interactive terminal (or --yes)."; return 1; }
    read -r -p "$prompt [y/N]: " answer
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

validate_paths() {
    [[ "$CONFIG" == /* && "$CONFIG" != *$'\n'* && "$CONFIG" != *$'\r'* ]] || {
        fail "Invalid keyd configuration path."
        return 1
    }
    [[ ! -L "$CONFIG" ]] || {
        fail "A symbolic-link keyd configuration was refused: $CONFIG"
        return 1
    }
    local path
    for path in "$DATA_HOME" "$BACKUP_ROOT" "$STATE_ROOT"; do
        [[ ! -L "$path" ]] || { fail "Unsafe ArchMind path refused: $path"; return 1; }
    done
}

package_installed() {
    pacman -Q keyd >/dev/null 2>&1
}

service_active() {
    systemctl is-active --quiet keyd.service 2>/dev/null
}

service_enabled() {
    systemctl is-enabled --quiet keyd.service 2>/dev/null
}

has_marker() {
    [[ -f "$CONFIG" ]] && grep -Fq "$MARKER" "$CONFIG"
}

has_exact_rule() {
    [[ -f "$CONFIG" ]] && grep -Eq \
        '^[[:space:]]*capslock[[:space:]]*=[[:space:]]*macro\([[:space:]]*capslock[[:space:]]*\)[[:space:]]*(#.*)?$' \
        "$CONFIG"
}

active_caps_rules() {
    [[ -f "$CONFIG" ]] || return 0
    grep -nEi '^[[:space:]]*(caps|capslock)[[:space:]]*=' "$CONFIG" || true
}

has_conflicting_caps_rule() {
    local rules exact_count total_count
    rules="$(active_caps_rules)"
    [[ -n "$rules" ]] || return 1
    total_count="$(printf '%s\n' "$rules" | sed '/^$/d' | wc -l)"
    exact_count="$(grep -Ec \
        '^[[:space:]]*capslock[[:space:]]*=[[:space:]]*macro\([[:space:]]*capslock[[:space:]]*\)[[:space:]]*(#.*)?$' \
        "$CONFIG" || true)"
    [[ "$total_count" -ne 1 || "$exact_count" -ne 1 ]]
}

sha256_file() {
    sha256sum -- "$1" | awk '{print $1}'
}

create_backup() {
    local stamp backup
    stamp="$(date +'%Y%m%d-%H%M%S')-$$"
    backup="$BACKUP_ROOT/default.conf-$stamp"
    umask 077
    mkdir -p -- "$BACKUP_ROOT"
    run_root cat -- "$CONFIG" > "$backup"
    chmod 600 -- "$backup"
    printf '%s' "$backup"
}

render_configuration() {
    local source="$1" destination="$2"
    local has_global=0 has_main=0 has_timeout=0 marker_present=0 exact_present=0

    grep -Eq '^[[:space:]]*\[global\][[:space:]]*$' "$source" && has_global=1
    grep -Eq '^[[:space:]]*\[main\][[:space:]]*$' "$source" && has_main=1
    grep -Eq '^[[:space:]]*macro_timeout[[:space:]]*=' "$source" && has_timeout=1
    grep -Fq "$MARKER" "$source" && marker_present=1
    grep -Eq \
        '^[[:space:]]*capslock[[:space:]]*=[[:space:]]*macro\([[:space:]]*capslock[[:space:]]*\)[[:space:]]*(#.*)?$' \
        "$source" && exact_present=1

    awk \
        -v has_global="$has_global" \
        -v has_main="$has_main" \
        -v has_timeout="$has_timeout" \
        -v marker_present="$marker_present" \
        -v exact_present="$exact_present" \
        -v marker="$MARKER" '
        BEGIN {
            if (!has_global) {
                print "[global]"
                print ""
                print "# ArchMind: prevents repeated Caps Lock macros while the key is held."
                print "macro_timeout = 600000"
                print ""
            }
        }
        /^[[:space:]]*\[global\][[:space:]]*$/ {
            print
            if (!has_timeout) {
                print ""
                print "# ArchMind: prevents repeated Caps Lock macros while the key is held."
                print "macro_timeout = 600000"
            }
            next
        }
        /^[[:space:]]*\[main\][[:space:]]*$/ {
            print
            if (!exact_present) {
                print ""
                if (!marker_present)
                    print "# " marker
                print "# Caps Lock without release delay."
                print "capslock = macro(capslock)"
            }
            next
        }
        /^[[:space:]]*capslock[[:space:]]*=[[:space:]]*macro\([[:space:]]*capslock[[:space:]]*\)[[:space:]]*(#.*)?$/ {
            if (!marker_present)
                print "# " marker
            print
            next
        }
        { print }
        END {
            if (!has_main) {
                print ""
                print "[main]"
                print ""
                if (!marker_present)
                    print "# " marker
                print "# Caps Lock without release delay."
                print "capslock = macro(capslock)"
            }
        }
    ' "$source" > "$destination"
}

write_state() {
    local mode="$1" backup="$2" installed_hash="$3"
    umask 077
    mkdir -p -- "$STATE_ROOT"
    {
        printf 'format=1\n'
        printf 'mode=%s\n' "$mode"
        printf 'backup=%s\n' "$backup"
        printf 'installed_hash=%s\n' "$installed_hash"
        printf 'created=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    } > "$STATE_FILE"
    chmod 600 -- "$STATE_FILE"
}

state_value() {
    local key="$1"
    [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] || return 1
    sed -n "s/^${key}=//p" "$STATE_FILE" | head -n 1
}

reload_keyd() {
    if ! run_root keyd reload; then
        warn "keyd reload failed; restarting the service."
        run_root systemctl restart keyd.service
    fi
}

apply_patch() {
    require_normal_user || return 1
    validate_paths || return 1
    has sudo || [[ "${ARCHMIND_TEST_SIMULATE:-0}" == "1" ]] || {
        fail "sudo is required to install and configure keyd."
        return 1
    }
    has pacman || { fail "Pacman was not found; this patch requires Arch Linux."; return 1; }

    if [[ -f "$CONFIG" ]] && has_conflicting_caps_rule; then
        fail "An existing Caps Lock remapping was found. Nothing was changed:"
        active_caps_rules >&2
        fail "Remove or review the conflict manually before applying this patch."
        return 2
    fi

    printf 'This optional patch installs keyd and changes %s.\n' "$CONFIG"
    confirm "Apply Caps Lock No Delay?" || { warn "Cancelled. Nothing was changed."; return 0; }

    if ! package_installed; then
        info "Installing keyd..."
        run_root pacman -S --needed keyd
    fi

    if [[ -f "$CONFIG" ]] && has_marker && has_exact_rule; then
        info "The ArchMind Caps Lock rule is already present."
    else
        local mode="created" backup="" source=""
        umask 077
        mkdir -p -- "$STATE_ROOT"
        TEMP_FILE="$(mktemp "$STATE_ROOT/default.conf.XXXXXX")"

        if [[ -f "$CONFIG" ]]; then
            mode="modified"
            backup="$(create_backup)"
            source="$CONFIG"
            info "Safety copy created: $backup"
        else
            source="$(mktemp "$STATE_ROOT/empty.XXXXXX")"
            : > "$source"
        fi

        render_configuration "$source" "$TEMP_FILE"
        [[ "$source" == "$CONFIG" ]] || rm -f -- "$source"
        run_root mkdir -p -- "$(dirname -- "$CONFIG")"
        run_root install -o root -g root -m 0644 -- "$TEMP_FILE" "$CONFIG"
        write_state "$mode" "$backup" "$(sha256_file "$TEMP_FILE")"
    fi

    info "Enabling keyd.service..."
    run_root systemctl enable --now keyd.service
    reload_keyd

    ok "Caps Lock No Delay is active. No logout or reboot is required."
}

show_status() {
    printf 'ArchMind Caps Lock No Delay\n\n'
    if package_installed; then printf 'keyd package ........ installed\n'; else printf 'keyd package ........ not installed\n'; fi
    if service_active; then printf 'keyd.service ........ active\n'; else printf 'keyd.service ........ inactive\n'; fi
    if service_enabled; then printf 'Startup ............. enabled\n'; else printf 'Startup ............. disabled\n'; fi
    if has_marker; then printf 'ArchMind marker ..... found\n'; else printf 'ArchMind marker ..... not found\n'; fi
    if has_exact_rule; then printf 'Caps Lock rule ...... found\n'; else printf 'Caps Lock rule ...... not found\n'; fi
    printf 'Configuration ....... %s\n' "$CONFIG"
}

remove_patch() {
    require_normal_user || return 1
    validate_paths || return 1
    [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] || {
        fail "No ArchMind rollback state was found. Nothing was changed."
        return 1
    }

    local mode backup installed_hash current_hash
    mode="$(state_value mode)"
    backup="$(state_value backup || true)"
    installed_hash="$(state_value installed_hash)"
    [[ "$mode" == "created" || "$mode" == "modified" ]] || {
        fail "Invalid rollback state. Nothing was changed."
        return 1
    }
    [[ -f "$CONFIG" && ! -L "$CONFIG" ]] || {
        fail "The managed configuration is missing or unsafe; rollback was refused."
        return 1
    }
    current_hash="$(sha256_file "$CONFIG")"
    [[ "$current_hash" == "$installed_hash" ]] || {
        fail "The keyd configuration changed after installation; automatic rollback was refused."
        fail "Review $CONFIG and the safety copy manually."
        return 2
    }

    confirm "Restore the configuration from before Caps Lock No Delay?" || {
        warn "Cancelled. Nothing was changed."
        return 0
    }

    if [[ "$mode" == "modified" ]]; then
        [[ "$backup" == "$BACKUP_ROOT"/* && -f "$backup" && ! -L "$backup" ]] || {
            fail "The recorded safety copy is unavailable; rollback was refused."
            return 1
        }
        run_root install -o root -g root -m 0644 -- "$backup" "$CONFIG"
        ok "Previous keyd configuration restored."
    else
        run_root rm -f -- "$CONFIG"
        ok "The ArchMind-created keyd configuration was removed."
    fi

    rm -f -- "$STATE_FILE"
    if service_active; then
        run_root systemctl restart keyd.service || warn "Restart keyd manually after reviewing its configuration."
    fi
    warn "The keyd package and service were retained to protect other possible mappings."
}

menu() {
    while true; do
        printf '\nArchMind — Caps Lock No Delay\n\n'
        printf '1) Status\n'
        printf '2) Apply patch\n'
        printf '3) Remove / restore previous configuration\n'
        printf '0) Back\n\n'
        local choice=""
        read -r -p "Choice: " choice || return 0
        case "$choice" in
            1) show_status ;;
            2) apply_patch ;;
            3) remove_patch ;;
            0) return 0 ;;
            *) warn "Invalid option." ;;
        esac
    done
}

main() {
    parse_args "$@"
    case "$ACTION" in
        menu) menu ;;
        status) show_status ;;
        apply) apply_patch ;;
        remove) remove_patch ;;
    esac
}

main "$@"
