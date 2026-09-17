#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly VERSION="1.5.18"
readonly PACKAGE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PAYLOAD_PROJECT="$PACKAGE_ROOT/payload/archmind"
readonly PAYLOAD_TOOLKIT="$PACKAGE_ROOT/payload/toolkit"
readonly CHECKSUM_FILE="$PACKAGE_ROOT/PAYLOAD.sha256"

readonly ARCHMIND_ROOT="$HOME/ArchMind"
readonly TARGET_SYSTEM="$ARCHMIND_ROOT/System"
readonly TARGET_PROJECT="$TARGET_SYSTEM/Core"
readonly TARGET_TOOLKIT="$TARGET_SYSTEM/Toolkit"
readonly TARGET_CONFIG="$ARCHMIND_ROOT/Config"
readonly TARGET_BIN="$HOME/.local/bin"
readonly BACKUP_BASE="$ARCHMIND_ROOT/Installer-Backups"
readonly TEMP_BASE="$ARCHMIND_ROOT/Temp"
readonly LEGACY_PROJECT="$HOME/.config/archmind"
readonly LEGACY_TOOLKIT="$HOME/.local/share/archmind-toolkit"
readonly TERMINAL_DESKTOP="$HOME/.local/share/applications/archmind-execute-terminal.desktop"

dry_run=0
assume_yes=0
check_only=0
organize_home=0
show_progress=1
progress_active=0
progress_percent=0
progress_started_ms=0
progress_now_ms=0
progress_line_open=0
stage_project=""
stage_toolkit=""
transaction_dir=""
project_backed_up=0
toolkit_backed_up=0
project_installed=0
toolkit_installed=0
legacy_project_backed_up=0
legacy_toolkit_backed_up=0
launcher_console_touched=0
launcher_compat_touched=0
launcher_monitor_touched=0
transaction_started=0

progress_clear() {
    if (( progress_line_open )); then
        printf '\r\033[2K'
        progress_line_open=0
    fi
}

info()  { progress_clear; printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()    { progress_clear; printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn()  { progress_clear; printf '\033[1;33m[WARNING]\033[0m %s\n' "$*"; }
error() { progress_clear; printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()   { error "$*"; exit 1; }

usage() {
    cat <<'HELP'
ArchMind 1.5.18 — portable installer

Usage:
  ./install.sh             Install or update with a safety copy
  ./install.sh --dry-run   Show the plan without changing files
  ./install.sh --check     Validate the package and exit
  ./install.sh --yes       Allow Zsh installation when it is missing
  ./install.sh --organize-home  Offer to organize loose .zsh copies in Home
  ./install.sh --no-progress    Disable the progress bar and minimum display time
  ./install.sh --help      Show this help

The installer operates only inside the user's Home directory. If Zsh is
missing, the only offered system change is installing the "zsh" package
through Pacman after confirmation.
HELP
}

parse_args() {
    while (( $# )); do
        case "$1" in
            --dry-run) dry_run=1 ;;
            --check) check_only=1 ;;
            --yes|-y) assume_yes=1 ;;
            --organize-home) organize_home=1 ;;
            --no-progress) show_progress=0 ;;
            --help|-h) usage; exit 0 ;;
            --version|-v) printf 'ArchMind installer %s\n' "$VERSION"; exit 0 ;;
            *) die "Unknown option: $1" ;;
        esac
        shift
    done
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

progress_clock() {
    # /proc/uptime is monotonic and is available on the supported Linux hosts.
    local uptime_value unused whole fraction
    IFS=' ' read -r uptime_value unused < /proc/uptime || return 1
    whole="${uptime_value%%.*}"
    fraction="${uptime_value#*.}000"
    fraction="${fraction:0:3}"
    [[ "$whole" =~ ^[0-9]+$ && "$fraction" =~ ^[0-9]+$ ]] || return 1
    progress_now_ms=$(( 10#$whole * 1000 + 10#$fraction ))
}

progress_start() {
    (( show_progress && ! check_only && ! dry_run )) || return 0
    [[ -t 0 && -t 1 && "${TERM:-dumb}" != dumb && -r /proc/uptime ]] || return 0
    command -v sleep >/dev/null 2>&1 || return 0
    progress_clock || return 0
    progress_started_ms="$progress_now_ms"
    progress_active=1
    info 'Step-based progress — minimum display time of 5 seconds.'
    progress_draw 0 'Verifying package'
}

progress_draw() {
    local percent="$1" label="$2" size columns width filled empty bar rest available
    progress_line_open=1
    size="$(stty size 2>/dev/null)" || size="0 80"
    columns="${size##* }"
    [[ "$columns" =~ ^[0-9]+$ ]] || columns=80
    (( columns > 0 )) || columns=80
    if (( columns < 20 )); then
        printf '\r\033[2K%3d%%' "$percent"
        return 0
    fi
    width=$(( columns / 3 ))
    (( width <= 24 )) || width=24
    filled=$(( percent * width / 100 ))
    empty=$(( width - filled ))
    printf -v bar '%*s' "$filled" ''
    printf -v rest '%*s' "$empty" ''
    bar="${bar// /█}"
    rest="${rest// /░}"
    available=$(( columns - width - 10 ))
    (( available >= 0 )) || available=0
    printf '\r\033[2K\033[1;36m[%s%s] %3d%%\033[0m %s' \
        "$bar" "$rest" "$percent" "${label:0:available}"
}

progress_advance() {
    local target="$1" label="$2" elapsed permitted
    (( progress_active )) || return 0
    # Advance only up to the last completed installation milestone. Time alone
    # can never complete a stage. Reserve the final 0.5 s to show success.
    while (( progress_percent < target )); do
        if ! progress_clock; then
            progress_active=0
            progress_clear
            return 0
        fi
        elapsed=$(( progress_now_ms - progress_started_ms ))
        permitted=$(( elapsed * 100 / 4500 ))
        (( permitted <= target )) || permitted="$target"
        if (( permitted > progress_percent )); then
            progress_percent="$permitted"
            progress_draw "$progress_percent" "$label"
        fi
        (( progress_percent >= target )) || sleep 0.05
    done
}

progress_finish() {
    (( progress_active )) || return 0
    progress_advance 100 'Installation complete'
    sleep 0.5
    printf '\n'
    progress_line_open=0
}

confirm() {
    local answer=""

    (( assume_yes )) && return 0
    [[ -t 0 ]] || return 1

    read -r -p "$1 [y/N]: " answer
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

verify_payload() {
    [[ -d "$PAYLOAD_PROJECT" ]] || die "Project missing from the package."
    [[ -x "$PAYLOAD_TOOLKIT/bin/archmind-console" ]] || \
        die "AFI launcher is missing or not executable."
    [[ -x "$PAYLOAD_TOOLKIT/bin/archmind" ]] || \
        die "Compatibility launcher is missing or not executable."
    [[ -f "$CHECKSUM_FILE" ]] || die "PAYLOAD.sha256 was not found."
    [[ -x "$PAYLOAD_TOOLKIT/bin/archmind-monitor" ]] || die "Live Monitor launcher is missing."
    local required_tool
    for required_tool in \
        live-monitor.py storage-info.py doctor-report.py runtime_files.py system-updates.py \
        maintenance_state.py hardware-profile.py pending-tasks.py update-guardian.py \
        operating-profiles.py cleanup-audit.py backup-catalog.py rollback-center.py \
        configure-gnome-drag-hover.py; do
        [[ -r "$PAYLOAD_PROJECT/tools/$required_tool" ]] || die "Missing tool: $required_tool"
    done

    local profile
    for profile in base terminal gaming audio development; do
        [[ -f "$PAYLOAD_TOOLKIT/profiles/${profile}.conf" ]] || \
            die "Installation profile missing: ${profile}.conf"
    done
    [[ -f "$PAYLOAD_TOOLKIT/modules/install.sh" ]] || \
        die "Package installation module is missing."
    [[ -x "$PAYLOAD_PROJECT/tools/configure-nautilus.sh" ]] || \
        die "Nautilus configurator is missing or not executable."
    [[ -x "$PAYLOAD_PROJECT/tools/configure-gnome-appearance.sh" ]] || \
        die "GNOME appearance configurator is missing or not executable."
    [[ -x "$PAYLOAD_PROJECT/tools/configure-gamemode-blur.sh" ]] || \
        die "GameMode + Blur configurator is missing or not executable."
    [[ -x "$PAYLOAD_PROJECT/tools/gamemode-blur.sh" ]] || \
        die "GameMode + Blur hook is missing or not executable."
    [[ -x "$PAYLOAD_PROJECT/tools/configure-wine-compatibility.sh" ]] || \
        die "Wine Compatibility Pack is missing or not executable."
    [[ -x "$PAYLOAD_PROJECT/tools/configure-capslock-nodelay.sh" ]] || \
        die "Caps Lock No Delay is missing or not executable."
    [[ -f "$PAYLOAD_PROJECT/tools/configure-firefox-chatgpt-emoji.py" ]] || \
        die "Firefox / ChatGPT Color Emoji Fix is missing."
    [[ -x "$PAYLOAD_PROJECT/tools/configure-nvibrant.sh" ]] || \
        die "NVIDIA Vibrance configurator is missing or not executable."
    [[ -x "$PAYLOAD_PROJECT/patches/plymouth/plymouth-patch.sh" ]] || \
        die "Plymouth patch is missing or not executable."
    [[ -x "$PAYLOAD_PROJECT/patches/plymouth/plymouth-transform.py" ]] || \
        die "Safe Plymouth patch transformer is missing."
    [[ -x "$PAYLOAD_PROJECT/tools/execute-in-terminal.sh" ]] || \
        die "Run-in-terminal helper is missing or not executable."
    [[ -x "$PAYLOAD_PROJECT/tools/organize-home-zsh.sh" ]] || \
        die "Zsh file organizer is missing or not executable."
    [[ -x "$PAYLOAD_PROJECT/tools/post-update-doctor.zsh" ]] || \
        die "Post-update diagnosis is missing or not executable."

    require_command sha256sum
    if ! (cd -- "$PACKAGE_ROOT" && sha256sum -c --quiet PAYLOAD.sha256); then
        die "Package integrity verification failed."
    fi

    if find "$PACKAGE_ROOT/payload" -type l -print -quit | grep -q .; then
        die "The payload contains an unexpected symbolic link."
    fi

    if grep -R -n -E \
        'archmind-legacy|Classic Console|legacy-open|/home/[^/[:space:]]+/|kitty|pacman -Sy([[:space:]]|$)' \
        "$PAYLOAD_PROJECT" "$PAYLOAD_TOOLKIT" >/dev/null 2>&1; then
        die "The payload contains an obsolete reference or non-portable path."
    fi

    require_command bash
    while IFS= read -r -d '' file; do
        bash -n "$file"
    done < <(find "$PAYLOAD_TOOLKIT" -type f -name '*.sh' -print0)
    bash -n "$PAYLOAD_TOOLKIT/bin/archmind-console"
    bash -n "$PAYLOAD_TOOLKIT/bin/archmind"
    bash -n "$PAYLOAD_TOOLKIT/bin/archmind-monitor"
    bash -n "$PAYLOAD_PROJECT/bin/archmind-manager"
    while IFS= read -r -d '' file; do
        bash -n "$file"
    done < <(find "$PAYLOAD_PROJECT" -type f -name '*.sh' -print0)

    if command -v python3 >/dev/null 2>&1; then
        while IFS= read -r -d '' file; do
            python3 -B -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_bytes(), sys.argv[1], "exec")' "$file"
        done < <(find "$PAYLOAD_PROJECT" -type f -name '*.py' -print0)
    fi

    while IFS= read -r -d '' file; do
        grep -Eq '^official=[[:alnum:]_.+@/-]+([[:space:]]+[[:alnum:]_.+@/-]+)*$' "$file" || \
            die "Invalid official package list: ${file##*/}"
        if grep -qE '^[[:space:]]+(official|aur)=' "$file"; then
            die "Invalid indented profile key: ${file##*/}"
        fi
    done < <(find "$PAYLOAD_TOOLKIT/profiles" -type f -name '*.conf' -print0)

    if command -v zsh >/dev/null 2>&1; then
        while IFS= read -r -d '' file; do
            zsh -n "$file"
        done < <(find "$PAYLOAD_PROJECT" -type f -name '*.zsh' -print0)
    else
        warn "Zsh syntax will be validated after installing the dependency."
    fi

    ok "ArchMind $VERSION package passed integrity and syntax validation."
}

ensure_zsh() {
    command -v zsh >/dev/null 2>&1 && return 0

    (( dry_run || check_only )) && {
        warn "Zsh is not installed; it must be installed before activation."
        return 0
    }

    command -v pacman >/dev/null 2>&1 || \
        die "Zsh is missing and Pacman was not found. Install Zsh and try again."
    command -v sudo >/dev/null 2>&1 || \
        die "Zsh is missing and sudo was not found. Install Zsh and try again."

    if ! confirm "Zsh is not installed. Install it now through Pacman?"; then
        die "Installation cancelled. Run: sudo pacman -S --needed zsh"
    fi

    sudo pacman -S --needed --noconfirm zsh
    command -v zsh >/dev/null 2>&1 || die "Zsh is still unavailable after installation."
}

ensure_path_in_shell_file() {
    local file="$1"
    local line='export PATH="$HOME/.local/bin:$PATH"'
    local backup_dir="$transaction_dir/shell-config"

    if [[ -e "$file" && ! -f "$file" ]]; then
        warn "PATH was not configured in a non-regular path: $file"
        return 0
    fi

    if [[ -e "$file" && ! -w "$file" ]]; then
        warn "Permission denied while configuring PATH in: $file"
        return 0
    fi

    if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
        return 0
    fi

    mkdir -p -- "$backup_dir"
    if [[ -f "$file" ]]; then
        cp -a -- "$file" "$backup_dir/${file##*/}"
    else
        : > "$file"
        chmod 600 -- "$file"
    fi

    printf '\n%s\n' "$line" >> "$file"
}

configure_user_path() {
    # A newly formatted machine may start in Bash even when ArchMind uses Zsh.
    # Configuring both prevents the launchers from appearing unavailable.
    ensure_path_in_shell_file "$HOME/.bashrc"
    ensure_path_in_shell_file "$HOME/.zshrc"
}

configure_zsh_links() {
    local zshrc="$HOME/.zshrc"
    local backup_dir="$transaction_dir/shell-config"
    local aliases_line='[[ -r "$HOME/ArchMind/Config/Zsh/aliases.zsh" ]] && source "$HOME/ArchMind/Config/Zsh/aliases.zsh"'
    local p10k_line='[[ -r "$HOME/ArchMind/Config/Zsh/p10k.zsh" ]] && source "$HOME/ArchMind/Config/Zsh/p10k.zsh"'

    [[ -f "$zshrc" && -w "$zshrc" ]] || return 0
    mkdir -p -- "$backup_dir"
    [[ -f "$backup_dir/.zshrc" ]] || cp -a -- "$zshrc" "$backup_dir/.zshrc"

    if [[ -f "$TARGET_CONFIG/Zsh/aliases.zsh" ]] && \
       [[ ! -e "$HOME/.zsh_aliases" || -L "$HOME/.zsh_aliases" ]] && \
       ! grep -qE '\.zsh_aliases|ArchMind/Config/Zsh/aliases\.zsh' "$zshrc"; then
        printf '\n%s\n' "$aliases_line" >> "$zshrc"
    fi
    if [[ -f "$TARGET_CONFIG/Zsh/p10k.zsh" ]] && \
       [[ ! -e "$HOME/.p10k.zsh" || -L "$HOME/.p10k.zsh" ]] && \
       ! grep -qE '\.p10k\.zsh|ArchMind/Config/Zsh/p10k\.zsh' "$zshrc"; then
        printf '\n%s\n' "$p10k_line" >> "$zshrc"
    fi
}

desktop_quote() {
    # Desktop Entry Exec has its own escaping, not shell quoting.
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//\$/\\\$}"
    value="${value//\`/\\\`}"
    value="${value//\\/\\\\}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\t'/\\t}"
    value="${value//$'\r'/\\r}"
    value="${value//%/%%}"
    printf '"%s"' "$value"
}

show_plan() {
    cat <<EOF_PLAN

INSTALLATION PLAN — NO CHANGES MADE

Unified root: $ARCHMIND_ROOT
Project:      $TARGET_PROJECT
Runtime:      $TARGET_TOOLKIT
Configuration: $TARGET_CONFIG
Commands:     $TARGET_BIN/archmind-console
              $TARGET_BIN/archmind
Safety copy:  $BACKUP_BASE
Version:      $VERSION

The existing project and runtime would be moved into a safety copy.
Current personal settings would be preserved during the update.
EOF_PLAN
}

safe_remove_stage() {
    local path="${1:-}"

    case "$path" in
        "$TEMP_BASE/".core-install.*|"$TEMP_BASE/".toolkit-install.*)
            [[ -e "$path" ]] && rm -rf -- "$path"
            ;;
        "") ;;
        *) warn "Cleanup refused for unexpected temporary path: $path" ;;
    esac
}

cleanup_stages() {
    safe_remove_stage "$stage_project"
    safe_remove_stage "$stage_toolkit"
}

restore_launcher() {
    local name="$1"
    local target="$TARGET_BIN/$name"
    local saved="$transaction_dir/bin/$name"

    [[ -e "$target" || -L "$target" ]] && rm -f -- "$target"
    [[ -e "$saved" || -L "$saved" ]] && mv -- "$saved" "$target"
}

rollback() {
    local status="${1:-1}"
    trap - ERR INT TERM HUP
    set +e

    if (( transaction_started )); then
        error "Installation failed; restoring the previous state."

        if [[ -L "$LEGACY_PROJECT" && "$(readlink -- "$LEGACY_PROJECT")" == "$TARGET_PROJECT" ]]; then
            rm -f -- "$LEGACY_PROJECT"
        fi
        if [[ -L "$LEGACY_TOOLKIT" && "$(readlink -- "$LEGACY_TOOLKIT")" == "$TARGET_TOOLKIT" ]]; then
            rm -f -- "$LEGACY_TOOLKIT"
        fi

        if (( launcher_console_touched )); then
            restore_launcher archmind-console
        fi
        if (( launcher_compat_touched )); then
            restore_launcher archmind
        fi
        if (( launcher_monitor_touched )); then
            restore_launcher archmind-monitor
        fi

        if (( project_installed )) && [[ -d "$TARGET_PROJECT" ]]; then
            mv -- "$TARGET_PROJECT" "$transaction_dir/failed-new-project"
        fi
        if (( project_backed_up )) && [[ -d "$transaction_dir/project" ]]; then
            mv -- "$transaction_dir/project" "$TARGET_PROJECT"
        fi

        if (( toolkit_installed )) && [[ -d "$TARGET_TOOLKIT" ]]; then
            mv -- "$TARGET_TOOLKIT" "$transaction_dir/failed-new-toolkit"
        fi
        if (( toolkit_backed_up )) && [[ -d "$transaction_dir/toolkit" ]]; then
            mv -- "$transaction_dir/toolkit" "$TARGET_TOOLKIT"
        fi

        if (( legacy_project_backed_up )) && [[ -d "$transaction_dir/legacy-project" ]]; then
            [[ -L "$LEGACY_PROJECT" ]] && rm -f -- "$LEGACY_PROJECT"
            mv -- "$transaction_dir/legacy-project" "$LEGACY_PROJECT"
        fi
        if (( legacy_toolkit_backed_up )) && [[ -d "$transaction_dir/legacy-toolkit" ]]; then
            [[ -L "$LEGACY_TOOLKIT" ]] && rm -f -- "$LEGACY_TOOLKIT"
            mv -- "$transaction_dir/legacy-toolkit" "$LEGACY_TOOLKIT"
        fi
        restore_transaction_metadata
    fi

    safe_remove_stage "$stage_project"
    safe_remove_stage "$stage_toolkit"
    exit "$status"
}

validate_existing_targets() {
    [[ "$HOME" != *$'\n'* && "$HOME" != *$'\r'* && "$HOME" != *$'\t'* ]] || \
        die 'Home paths containing control characters are not supported.'
    local directory
    for directory in "$ARCHMIND_ROOT" "$TARGET_SYSTEM" "$TARGET_CONFIG" \
        "$TARGET_CONFIG/Zsh" "$BACKUP_BASE" "$TEMP_BASE" \
        "$HOME/.local" "$TARGET_BIN" "$HOME/.local/share" \
        "$HOME/.local/share/applications" "$HOME/.config"; do
        [[ ! -L "$directory" ]] || die "Refused: directory is a symbolic link: $directory"
        [[ ! -e "$directory" || -d "$directory" ]] || die "Refused: not a directory: $directory"
    done
    local file
    for file in "$HOME/.zshrc" "$HOME/.bashrc" "$TERMINAL_DESKTOP" \
        "$TARGET_CONFIG/settings.zsh" "$TARGET_CONFIG/archmind.conf"; do
        [[ ! -L "$file" ]] || die "Refused: integration file is a symbolic link: $file"
        [[ ! -e "$file" || ( -f "$file" && -w "$file" ) ]] || \
            die "Refused: integration target is not a writable regular file: $file"
    done
    [[ ! -L "$TARGET_PROJECT" ]] || \
        die "Refused: $TARGET_PROJECT is a symbolic link."
    [[ ! -L "$TARGET_TOOLKIT" ]] || \
        die "Refused: $TARGET_TOOLKIT is a symbolic link."
    [[ ! -e "$TARGET_PROJECT" || -d "$TARGET_PROJECT" ]] || \
        die "Refused: $TARGET_PROJECT exists and is not a directory."
    [[ ! -e "$TARGET_TOOLKIT" || -d "$TARGET_TOOLKIT" ]] || \
        die "Refused: $TARGET_TOOLKIT exists and is not a directory."

    local name target
    for name in archmind-console archmind archmind-monitor; do
        target="$TARGET_BIN/$name"
        if [[ -d "$target" && ! -L "$target" ]]; then
            die "Refused: $target is a directory."
        fi
    done
}

prepare_stages() {
    mkdir -p -- "$TARGET_SYSTEM" "$TARGET_CONFIG" "$TEMP_BASE"

    stage_project="$(mktemp -d "$TEMP_BASE/.core-install.XXXXXX")"
    stage_toolkit="$(mktemp -d "$TEMP_BASE/.toolkit-install.XXXXXX")"

    cp -a -- "$PAYLOAD_PROJECT/." "$stage_project/"
    cp -a -- "$PAYLOAD_TOOLKIT/." "$stage_toolkit/"

    # During an update, retain only the user's personal preferences.
    local settings_source=""
    if [[ -f "$TARGET_CONFIG/settings.zsh" && ! -L "$TARGET_CONFIG/settings.zsh" ]]; then
        settings_source="$TARGET_CONFIG/settings.zsh"
    elif [[ -f "$TARGET_PROJECT/config/settings.zsh" && \
            ! -L "$TARGET_PROJECT/config/settings.zsh" ]]; then
        settings_source="$TARGET_PROJECT/config/settings.zsh"
    elif [[ -f "$LEGACY_PROJECT/config/settings.zsh" && \
            ! -L "$LEGACY_PROJECT/config/settings.zsh" ]]; then
        settings_source="$LEGACY_PROJECT/config/settings.zsh"
    fi
    if [[ -n "$settings_source" ]]; then
        if [[ "$settings_source" != "$TARGET_CONFIG/settings.zsh" ]]; then
            cp -a -- "$settings_source" "$TARGET_CONFIG/settings.zsh"
        fi
    elif [[ ! -f "$TARGET_CONFIG/settings.zsh" ]]; then
        cp -a -- "$PAYLOAD_PROJECT/config/settings.zsh" "$TARGET_CONFIG/settings.zsh"
    fi
    local config_source=""
    if [[ -f "$TARGET_CONFIG/archmind.conf" && ! -L "$TARGET_CONFIG/archmind.conf" ]]; then
        config_source="$TARGET_CONFIG/archmind.conf"
    elif [[ -f "$TARGET_PROJECT/config/archmind.conf" && \
            ! -L "$TARGET_PROJECT/config/archmind.conf" ]]; then
        config_source="$TARGET_PROJECT/config/archmind.conf"
    elif [[ -f "$LEGACY_PROJECT/config/archmind.conf" && \
            ! -L "$LEGACY_PROJECT/config/archmind.conf" ]]; then
        config_source="$LEGACY_PROJECT/config/archmind.conf"
    fi
    if [[ -n "$config_source" && "$config_source" != "$TARGET_CONFIG/archmind.conf" ]]; then
        cp -a -- "$config_source" "$TARGET_CONFIG/archmind.conf"
    elif [[ -z "$config_source" ]]; then
        cp -a -- "$PAYLOAD_PROJECT/config/archmind.conf" "$TARGET_CONFIG/archmind.conf"
    fi

    chmod 755 -- \
        "$stage_project/bin/archmind-manager" \
        "$stage_project/console/main.zsh" \
        "$stage_toolkit/bin/archmind-console" \
        "$stage_toolkit/bin/archmind" \
        "$stage_toolkit/bin/archmind-monitor" \
        "$stage_toolkit/install.sh" \
        "$stage_project/tools/configure-nautilus.sh" \
        "$stage_project/tools/configure-gnome-appearance.sh" \
        "$stage_project/tools/configure-gamemode-blur.sh" \
        "$stage_project/tools/gamemode-blur.sh" \
        "$stage_project/tools/configure-gnome-drag-hover.py" \
        "$stage_project/tools/configure-wine-compatibility.sh" \
        "$stage_project/tools/configure-capslock-nodelay.sh" \
        "$stage_project/tools/configure-firefox-chatgpt-emoji.py" \
        "$stage_project/tools/configure-nvibrant.sh" \
        "$stage_project/tools/hardware-profile.py" \
        "$stage_project/tools/pending-tasks.py" \
        "$stage_project/tools/update-guardian.py" \
        "$stage_project/tools/operating-profiles.py" \
        "$stage_project/tools/cleanup-audit.py" \
        "$stage_project/tools/backup-catalog.py" \
        "$stage_project/tools/rollback-center.py" \
        "$stage_project/tools/post-update-doctor.zsh" \
        "$stage_project/patches/plymouth/plymouth-patch.sh" \
        "$stage_project/patches/plymouth/plymouth-transform.py" \
        "$stage_project/tools/execute-in-terminal.sh"

    bash -n "$stage_project/bin/archmind-manager"
    bash -n "$stage_project/tools/configure-nautilus.sh"
    bash -n "$stage_project/tools/configure-gnome-appearance.sh"
    bash -n "$stage_project/tools/configure-gamemode-blur.sh"
    bash -n "$stage_project/tools/gamemode-blur.sh"
    bash -n "$stage_project/tools/configure-wine-compatibility.sh"
    bash -n "$stage_project/tools/configure-capslock-nodelay.sh"
    bash -n "$stage_project/tools/configure-nvibrant.sh"
    bash -n "$stage_project/patches/plymouth/plymouth-patch.sh"
    bash -n "$stage_project/tools/execute-in-terminal.sh"
    bash -n "$stage_toolkit/bin/archmind-console"
    bash -n "$stage_toolkit/bin/archmind"
    bash -n "$stage_toolkit/bin/archmind-monitor"
    while IFS= read -r -d '' file; do
        bash -n "$file"
    done < <(find "$stage_toolkit" -type f -name '*.sh' -print0)
    while IFS= read -r -d '' file; do
        zsh -n "$file"
    done < <(find "$stage_project" -type f -name '*.zsh' -print0)
}

migrate_legacy_targets() {
    mkdir -p -- "$HOME/.config" "$HOME/.local/share"

    if [[ -d "$LEGACY_PROJECT" && ! -L "$LEGACY_PROJECT" && \
          "$LEGACY_PROJECT" != "$TARGET_PROJECT" ]]; then
        mv -- "$LEGACY_PROJECT" "$transaction_dir/legacy-project"
        legacy_project_backed_up=1
    fi
    if [[ -d "$LEGACY_TOOLKIT" && ! -L "$LEGACY_TOOLKIT" && \
          "$LEGACY_TOOLKIT" != "$TARGET_TOOLKIT" ]]; then
        mv -- "$LEGACY_TOOLKIT" "$transaction_dir/legacy-toolkit"
        legacy_toolkit_backed_up=1
    fi
}

migrate_home_zsh_files() {
    local source destination
    mkdir -p -- "$TARGET_CONFIG/Zsh" "$transaction_dir/home-files"

    for source in "$HOME/.zsh_aliases" "$HOME/.p10k.zsh"; do
        [[ -f "$source" && ! -L "$source" ]] || continue
        case "${source##*/}" in
            .zsh_aliases) destination="$TARGET_CONFIG/Zsh/aliases.zsh" ;;
            .p10k.zsh) destination="$TARGET_CONFIG/Zsh/p10k.zsh" ;;
        esac
        if [[ -e "$destination" || -L "$destination" ]]; then
            if [[ -L "$destination" || ! -f "$destination" ]] || ! cmp -s -- "$source" "$destination"; then
                warn "Conflict between $source and $destination: the original was preserved."
                continue
            fi
        else
            cp -a -- "$source" "$destination"
        fi
        mv -- "$source" "$transaction_dir/home-files/${source##*/}"
        # Hidden compatibility links preserve direct and indirect shell imports.
        ln -s -- "$destination" "$source"
    done
}

install_compatibility_links() {
    mkdir -p -- "$HOME/.config" "$HOME/.local/share"

    [[ -L "$LEGACY_PROJECT" ]] && rm -f -- "$LEGACY_PROJECT"
    [[ -L "$LEGACY_TOOLKIT" ]] && rm -f -- "$LEGACY_TOOLKIT"
    ln -s -- "$TARGET_PROJECT" "$LEGACY_PROJECT"
    ln -s -- "$TARGET_TOOLKIT" "$LEGACY_TOOLKIT"
}

install_terminal_file_handler() {
    local executor
    executor="$(desktop_quote "$TARGET_PROJECT/tools/execute-in-terminal.sh")"
    mkdir -p -- "${TERMINAL_DESKTOP%/*}"
    cat > "$TERMINAL_DESKTOP" <<EOF_DESKTOP
[Desktop Entry]
Type=Application
Name=Run in Terminal
Comment=Run the selected file inside a terminal
Icon=utilities-terminal
Exec=$executor %f
Terminal=true
NoDisplay=false
StartupNotify=true
MimeType=application/x-executable;application/x-shellscript;text/x-shellscript;
Categories=System;Utility;
EOF_DESKTOP
    chmod 644 -- "$TERMINAL_DESKTOP"
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "${TERMINAL_DESKTOP%/*}" || true
}

begin_transaction() {
    local stamp
    stamp="$(date +'%Y%m%d-%H%M%S')"

    mkdir -p -- "$BACKUP_BASE"
    transaction_dir="$BACKUP_BASE/archmind-before-${VERSION}-${stamp}-$$"
    mkdir -p -- "$transaction_dir/bin"
    mkdir -p -- "$transaction_dir/metadata"
    local name
    for name in .zshrc .bashrc .zsh_aliases .p10k.zsh; do
        if [[ -e "$HOME/$name" || -L "$HOME/$name" ]]; then
            cp -a -- "$HOME/$name" "$transaction_dir/metadata/$name"
        fi
    done
    if [[ -d "$TARGET_CONFIG" ]]; then
        cp -a -- "$TARGET_CONFIG" "$transaction_dir/metadata/Config"
    fi
    if [[ -f "$TERMINAL_DESKTOP" ]]; then
        cp -a -- "$TERMINAL_DESKTOP" "$transaction_dir/metadata/terminal.desktop"
    fi
    [[ ! -L "$LEGACY_PROJECT" ]] || cp -a -- "$LEGACY_PROJECT" "$transaction_dir/metadata/core-link"
    [[ ! -L "$LEGACY_TOOLKIT" ]] || cp -a -- "$LEGACY_TOOLKIT" "$transaction_dir/metadata/toolkit-link"
    transaction_started=1
    trap 'rollback "$?"' ERR
    trap 'rollback 130' INT
    trap 'rollback 143' TERM HUP
}

restore_transaction_metadata() {
    local name target saved
    for name in .zshrc .bashrc .zsh_aliases .p10k.zsh; do
        target="$HOME/$name"
        saved="$transaction_dir/metadata/$name"
        [[ ! -f "$target" && ! -L "$target" ]] || rm -f -- "$target"
        [[ ! -e "$saved" && ! -L "$saved" ]] || cp -a -- "$saved" "$target"
    done
    if [[ -d "$TARGET_CONFIG" ]]; then
        mv -- "$TARGET_CONFIG" "$transaction_dir/failed-new-config"
    fi
    [[ ! -d "$transaction_dir/metadata/Config" ]] || \
        cp -a -- "$transaction_dir/metadata/Config" "$TARGET_CONFIG"
    [[ ! -f "$TERMINAL_DESKTOP" ]] || rm -f -- "$TERMINAL_DESKTOP"
    [[ ! -f "$transaction_dir/metadata/terminal.desktop" ]] || \
        cp -a -- "$transaction_dir/metadata/terminal.desktop" "$TERMINAL_DESKTOP"
    [[ ! -L "$transaction_dir/metadata/core-link" ]] || \
        cp -a -- "$transaction_dir/metadata/core-link" "$LEGACY_PROJECT"
    [[ ! -L "$transaction_dir/metadata/toolkit-link" ]] || \
        cp -a -- "$transaction_dir/metadata/toolkit-link" "$LEGACY_TOOLKIT"
    return 0
}

backup_and_replace() {
    local name target

    if [[ -d "$TARGET_PROJECT" ]]; then
        mv -- "$TARGET_PROJECT" "$transaction_dir/project"
        project_backed_up=1
    fi
    mv -- "$stage_project" "$TARGET_PROJECT"
    stage_project=""
    project_installed=1

    if [[ -d "$TARGET_TOOLKIT" ]]; then
        mv -- "$TARGET_TOOLKIT" "$transaction_dir/toolkit"
        toolkit_backed_up=1
    fi
    mv -- "$stage_toolkit" "$TARGET_TOOLKIT"
    stage_toolkit=""
    toolkit_installed=1

    install_compatibility_links

    mkdir -p -- "$TARGET_BIN"
    for name in archmind-console archmind archmind-monitor; do
        target="$TARGET_BIN/$name"
        case "$name" in
            archmind-console) launcher_console_touched=1 ;;
            archmind) launcher_compat_touched=1 ;;
            archmind-monitor) launcher_monitor_touched=1 ;;
        esac
        if [[ -e "$target" || -L "$target" ]]; then
            mv -- "$target" "$transaction_dir/bin/$name"
        fi
        if [[ "$name" == archmind-monitor ]]; then
            ln -s -- "$TARGET_TOOLKIT/bin/archmind-monitor" "$target"
        else
            ln -s -- "$TARGET_TOOLKIT/bin/archmind-console" "$target"
        fi
    done
}

write_install_record() {
    cat > "$transaction_dir/INSTALLATION.txt" <<EOF_RECORD
ArchMind $VERSION
Installed on: $(date --iso-8601=seconds)
Project: $TARGET_PROJECT
Runtime: $TARGET_TOOLKIT
Unified root: $ARCHMIND_ROOT
Configuration: $TARGET_CONFIG

This directory contains the previous state that was replaced, when available.
EOF_RECORD
}

main() {
    parse_args "$@"

    require_command find
    require_command grep
    require_command cp
    require_command mv
    require_command ln
    require_command readlink
    require_command mktemp
    require_command stty
    if (( ! dry_run && ! check_only && EUID == 0 )); then
        die "Run as your normal user, not as root."
    fi
    ensure_zsh
    progress_start
    verify_payload
    progress_advance 15 'Package validated'

    (( check_only )) && exit 0

    if (( dry_run )); then
        show_plan
        exit 0
    fi

    validate_existing_targets
    trap cleanup_stages EXIT
    begin_transaction
    progress_advance 30 'Safety copy created'
    prepare_stages
    progress_advance 50 'Files prepared'
    migrate_legacy_targets
    migrate_home_zsh_files
    backup_and_replace
    progress_advance 75 'Files installed'
    write_install_record

    configure_user_path
    configure_zsh_links
    install_terminal_file_handler
    progress_advance 95 'Integrations configured'

    trap - ERR INT TERM HUP
    transaction_started=0
    progress_finish

    if (( organize_home )); then
        bash "$TARGET_PROJECT/tools/organize-home-zsh.sh" --offer || \
            warn ".zsh organization was not completed; the installation was preserved."
    fi

    ok "ArchMind $VERSION installed successfully."
    printf '\nMain interface: archmind-console\n'
    printf 'Compatible command: archmind\n'
    printf 'Safety copy:        %s\n' "$transaction_dir"
    printf 'ArchMind root:       %s\n' "$ARCHMIND_ROOT"

    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        warn '~/.local/bin was configured for Bash and Zsh, but the current session has not loaded it yet.'
        printf '%s\n' 'Reopen the terminal or run: export PATH="$HOME/.local/bin:$PATH"'
    fi
}

main "$@"
