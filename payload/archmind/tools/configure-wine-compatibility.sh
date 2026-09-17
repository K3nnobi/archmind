#!/usr/bin/env bash
# Optional Wine Compatibility Pack for one explicitly selected Wine prefix.

set -uo pipefail
IFS=$'\n\t'

readonly DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}"
readonly LOG_ROOT="$DATA_HOME/Logs/Wine-Compatibility"
readonly BACKUP_ROOT="$DATA_HOME/Installer-Backups/Wine"
readonly RECEIPT_ROOT="$DATA_HOME/Config/Wine"

PREFIX_INPUT="${WINEPREFIX:-$HOME/.wine}"
PREFIX=""
ACTION="menu"
ASSUME_YES=0
LOG_FILE=""
PREFIX_WAS_READY=0
BACKUP_CREATED=""
FAILURES=0
declare -a INSTALLED_VERBS=()

info() { printf '\033[1;36m[i]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
has()  { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<'EOF'
ArchMind Wine Compatibility Pack

Usage:
  configure-wine-compatibility.sh [--prefix PATH] --menu
  configure-wine-compatibility.sh [--prefix PATH] --status
  configure-wine-compatibility.sh [--prefix PATH] --plan
  configure-wine-compatibility.sh [--prefix PATH] --install-base
  configure-wine-compatibility.sh [--prefix PATH] --apply-recommended
  configure-wine-compatibility.sh [--prefix PATH] --apply-core
  configure-wine-compatibility.sh [--prefix PATH] --apply-modern-vc
  configure-wine-compatibility.sh [--prefix PATH] --apply-gaming
  configure-wine-compatibility.sh [--prefix PATH] --apply-dxvk
  configure-wine-compatibility.sh [--prefix PATH] --apply-7zip
  configure-wine-compatibility.sh [--prefix PATH] --apply-dotnet48
  configure-wine-compatibility.sh [--prefix PATH] --backup
  configure-wine-compatibility.sh [--prefix PATH] --list-installed

The default prefix is ~/.wine. Mutating actions require confirmation and create
a safety copy of an existing prefix. --yes accepts ordinary confirmations, but
never accepts the special DOTNET48 confirmation.
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --prefix)
                (($# >= 2)) || { fail "--prefix requires a path."; return 2; }
                PREFIX_INPUT="$2"
                shift
                ;;
            --menu) ACTION="menu" ;;
            --status) ACTION="status" ;;
            --plan) ACTION="plan" ;;
            --install-base) ACTION="install-base" ;;
            --apply-recommended) ACTION="recommended" ;;
            --apply-core) ACTION="core" ;;
            --apply-modern-vc) ACTION="modern-vc" ;;
            --apply-gaming) ACTION="gaming" ;;
            --apply-dxvk) ACTION="dxvk" ;;
            --apply-7zip) ACTION="7zip" ;;
            --apply-dotnet48) ACTION="dotnet48" ;;
            --backup) ACTION="backup" ;;
            --list-installed) ACTION="list" ;;
            --yes|-y) ASSUME_YES=1 ;;
            --help|-h) usage; exit 0 ;;
            *) fail "Unknown option: $1"; usage; return 2 ;;
        esac
        shift
    done
}

require_normal_user() {
    if ((EUID == 0)) && [[ "${ARCHMIND_TEST_SIMULATE:-0}" != "1" ]]; then
        fail "Run this module as your normal user, without sudo."
        return 1
    fi
}

normalize_prefix() {
    local candidate home_real
    [[ -n "$PREFIX_INPUT" && "$PREFIX_INPUT" != *$'\n'* && "$PREFIX_INPUT" != *$'\r'* ]] || {
        fail "The Wine prefix path is empty or contains control characters."
        return 1
    }
    case "$PREFIX_INPUT" in
        '~') candidate="$HOME" ;;
        '~/'*) candidate="$HOME/${PREFIX_INPUT#\~/}" ;;
        *) candidate="$PREFIX_INPUT" ;;
    esac
    [[ "$candidate" == /* ]] || candidate="$PWD/$candidate"
    [[ ! -L "$candidate" ]] || {
        fail "A symbolic-link prefix was refused: $candidate"
        return 1
    }
    has realpath || { fail "realpath is required to validate the prefix."; return 1; }
    home_real="$(realpath -e -- "$HOME" 2>/dev/null)" || {
        fail "The Home directory could not be resolved safely."
        return 1
    }
    PREFIX="$(realpath -m -- "$candidate" 2>/dev/null)" || return 1
    [[ "$PREFIX" == "$home_real"/* ]] || {
        fail "For safety, Wine prefixes must remain inside your Home directory."
        return 1
    }
    [[ "$PREFIX" != "$home_real" ]] || {
        fail "The Home directory itself cannot be used as a Wine prefix."
        return 1
    }
    case "${PREFIX,,}" in
        */steamapps/compatdata/*|*/proton*/pfx|*/proton-pfx/*)
            fail "A Proton/Steam prefix was refused. Do not mix Proton with regular Wine."
            return 1
            ;;
    esac
    [[ ! -e "$PREFIX" || -d "$PREFIX" ]] || {
        fail "The selected prefix path is not a directory."
        return 1
    }
}

prefix_ready() {
    [[ -d "$PREFIX/drive_c" && -f "$PREFIX/system.reg" && -f "$PREFIX/user.reg" &&
       ! -L "$PREFIX/drive_c" && ! -L "$PREFIX/system.reg" && ! -L "$PREFIX/user.reg" ]]
}

prefix_has_unknown_content() {
    [[ -d "$PREFIX" ]] || return 1
    [[ -n "$(find "$PREFIX" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

validate_archmind_directories() {
    local current
    for current in "$DATA_HOME" "$DATA_HOME/Logs" "$DATA_HOME/Installer-Backups" "$DATA_HOME/Config"; do
        [[ ! -L "$current" ]] || { fail "Unsafe ArchMind directory refused: $current"; return 1; }
    done
    [[ ! -L "$LOG_ROOT" && ! -L "$BACKUP_ROOT" && ! -L "$RECEIPT_ROOT" ]] || {
        fail "Unsafe Wine Compatibility directory refused."
        return 1
    }
}

confirm_action() {
    local prompt="$1" answer=""
    ((ASSUME_YES)) && return 0
    [[ -t 0 ]] || { fail "Confirmation requires an interactive terminal (or --yes)."; return 1; }
    read -r -p "$prompt [y/N]: " answer
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

init_log() {
    local label="$1" stamp
    validate_archmind_directories || return 1
    umask 077
    mkdir -p -- "$LOG_ROOT" "$BACKUP_ROOT" "$RECEIPT_ROOT"
    chmod 700 -- "$LOG_ROOT" "$BACKUP_ROOT" "$RECEIPT_ROOT" 2>/dev/null || true
    stamp="$(date -u +'%Y%m%dT%H%M%SZ')-$BASHPID"
    LOG_FILE="$LOG_ROOT/${label}-${stamp}.log"
    BACKUP_CREATED=""
    FAILURES=0
    : > "$LOG_FILE"
    chmod 600 -- "$LOG_FILE"
    {
        printf 'ArchMind Wine Compatibility Pack\n'
        printf 'Date: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        printf 'Prefix: %s\n' "$PREFIX"
        printf 'Action: %s\n\n' "$label"
    } >> "$LOG_FILE"
}

run_logged() {
    local label="$1"
    shift
    info "$label"
    printf '\n[%s]\n' "$label" >> "$LOG_FILE"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    local -a pipeline_status=("${PIPESTATUS[@]}")
    local status=${pipeline_status[0]}
    ((pipeline_status[1] == 0)) || status=${pipeline_status[1]}
    printf '[exit=%s]\n' "$status" >> "$LOG_FILE" 2>/dev/null || return 1
    return "$status"
}

prefix_label() {
    local name="${PREFIX##*/}"
    name="${name//[^[:alnum:]_.-]/_}"
    printf '%s' "${name:-wine-prefix}"
}

prefix_size() {
    du -sh -- "$PREFIX" 2>/dev/null | awk '{print $1}'
}

create_backup() {
    prefix_ready || return 0
    [[ -z "$BACKUP_CREATED" ]] || return 0
    has wineserver || { fail "wineserver is required before copying an active prefix."; return 1; }
    local destination stamp metadata
    stamp="$(date +'%Y%m%d-%H%M%S')-$BASHPID"
    destination="$BACKUP_ROOT/$(prefix_label)-pre-compat-$stamp"
    [[ ! -e "$destination" && ! -L "$destination" ]] || {
        fail "Backup destination already exists: $destination"
        return 1
    }
    info "Existing prefix size: $(prefix_size || printf unknown)"
    run_logged "Stopping Wine processes before the safety copy" \
        env WINEPREFIX="$PREFIX" wineserver -k || return 1
    info "Creating mandatory safety copy..."
    if ! cp -a --reflink=auto -- "$PREFIX" "$destination"; then
        [[ "$destination" == "$BACKUP_ROOT"/* ]] && rm -rf -- "$destination"
        fail "The safety copy failed; the prefix was not modified."
        return 1
    fi
    metadata="$destination/.archmind-wine-backup"
    {
        printf 'format=1\n'
        printf 'prefix=%s\n' "$PREFIX"
        printf 'created=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    } > "$metadata"
    chmod 600 -- "$metadata" 2>/dev/null || true
    BACKUP_CREATED="$destination"
    ok "Safety copy: $destination"
}

require_runtime_tools() {
    local missing=() command
    for command in wine wineboot wineserver winetricks cabextract unzip; do
        has "$command" || missing+=("$command")
    done
    if ! has 7z && ! has 7zz; then
        missing+=("7zip")
    fi
    ((${#missing[@]} == 0)) || {
        fail "Missing Wine base tools: ${missing[*]}"
        printf 'Use --install-base first.\n' >&2
        return 1
    }
}

initialize_prefix() {
    if prefix_ready; then
        PREFIX_WAS_READY=1
        return 0
    fi
    if prefix_has_unknown_content; then
        fail "The selected directory is not a valid Wine prefix and is not empty."
        return 1
    fi
    mkdir -p -- "$PREFIX"
    local architecture="${ARCHMIND_WINEARCH:-win64}"
    [[ "$architecture" == "win32" || "$architecture" == "win64" ]] || {
        fail "ARCHMIND_WINEARCH must be win32 or win64."
        return 1
    }
    run_logged "Initializing a new ${architecture} Wine prefix" \
        env WINEPREFIX="$PREFIX" WINEARCH="$architecture" wineboot -u || return 1
    prefix_ready || { fail "Wine did not create a valid prefix."; return 1; }
    ok "Wine prefix initialized: $PREFIX"
}

prepare_mutation() {
    local label="$1" prompt="$2"
    require_normal_user || return 1
    normalize_prefix || return 1
    require_runtime_tools || return 1
    PREFIX_WAS_READY=0
    prefix_ready && PREFIX_WAS_READY=1
    if ! prefix_ready && prefix_has_unknown_content; then
        fail "The selected directory contains files but is not a valid Wine prefix."
        return 1
    fi
    printf 'Selected prefix: %s\n' "$PREFIX"
    confirm_action "$prompt" || { warn "Cancelled. The prefix was not modified."; return 1; }
    init_log "$label" || return 1
    if ((PREFIX_WAS_READY)); then
        create_backup || return 1
    fi
    initialize_prefix || return 1
    load_installed_verbs
}

load_installed_verbs() {
    INSTALLED_VERBS=()
    prefix_ready || return 0
    mapfile -t INSTALLED_VERBS < <(
        env WINEPREFIX="$PREFIX" WINETRICKS_GUI=none winetricks list-installed 2>/dev/null |
            sed -n '/^[[:alnum:]_.+-][[:alnum:]_.+-]*$/p' |
            LC_ALL=C sort -u
    )
}

load_installed_verbs_from_log() {
    INSTALLED_VERBS=()
    [[ -f "$PREFIX/winetricks.log" && ! -L "$PREFIX/winetricks.log" ]] || return 0
    mapfile -t INSTALLED_VERBS < <(
        sed -n '/^[[:alnum:]_.+-][[:alnum:]_.+-]*$/p' "$PREFIX/winetricks.log" |
            LC_ALL=C sort -u
    )
}

verb_installed() {
    local verb="$1" item
    for item in "${INSTALLED_VERBS[@]}"; do
        [[ "$item" == "$verb" ]] && return 0
    done
    return 1
}

run_verb() {
    local verb="$1"
    if verb_installed "$verb"; then
        ok "$verb is already installed; skipped."
        return 0
    fi
    if run_logged "Installing Winetricks verb: $verb" \
        env WINEPREFIX="$PREFIX" WINETRICKS_GUI=none winetricks -q "$verb"; then
        INSTALLED_VERBS+=("$verb")
        ok "$verb installed."
        return 0
    fi
    warn "$verb failed. Review: $LOG_FILE"
    FAILURES=$((FAILURES + 1))
    return 1
}

prefix_architecture() {
    if [[ -f "$PREFIX/system.reg" ]] && grep -Fq '#arch=win64' "$PREFIX/system.reg"; then
        printf 'win64'
    else
        printf 'win32'
    fi
}

registry_runtime_installed() {
    local architecture="$1" key output
    key="HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\$architecture"
    output="$(env WINEPREFIX="$PREFIX" wine reg query "$key" 2>/dev/null || true)"
    grep -Eqi 'Installed[[:space:]]+REG_DWORD[[:space:]]+0x0*1([^[:xdigit:]]|$)' <<< "$output" &&
        grep -Eqi 'Version[[:space:]]+REG_SZ[[:space:]]+v?14\.' <<< "$output"
}

modern_vc_installed() {
    registry_runtime_installed x86 || return 1
    [[ "$(prefix_architecture)" == "win32" ]] || registry_runtime_installed x64
}

write_receipt() {
    local action="$1" identifier temporary home_real relative
    identifier="$(printf '%s' "$PREFIX" | sha256sum | awk '{print substr($1,1,16)}')"
    home_real="$(realpath -e -- "$HOME")"
    relative="${PREFIX#"$home_real"/}"
    temporary="$(mktemp "$RECEIPT_ROOT/.wine-pack.XXXXXX")" || return 1
    {
        printf 'format=1\n'
        printf 'prefix_relative=%s\n' "$relative"
        printf 'architecture=%s\n' "$(prefix_architecture)"
        printf 'last_action=%s\n' "$action"
        printf 'last_run=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        printf 'log_relative=%s\n' "${LOG_FILE#"$DATA_HOME"/}"
    } > "$temporary"
    chmod 600 -- "$temporary"
    mv -- "$temporary" "$RECEIPT_ROOT/prefix-$identifier.conf"
}

finish_action() {
    local action="$1"
    write_receipt "$action" || warn "The portable ArchMind receipt could not be saved."
    printf '\nLog: %s\n' "$LOG_FILE"
    [[ -z "$BACKUP_CREATED" ]] || printf 'Safety copy: %s\n' "$BACKUP_CREATED"
    if ((FAILURES)); then
        fail "$FAILURES component(s) failed; successful components were preserved."
        return 1
    fi
    ok "Wine Compatibility action completed."
}

apply_core_verbs() {
    local verb
    local -a verbs=(
        corefonts
        vcrun2005 vcrun2008 vcrun2010 vcrun2012 vcrun2013
        d3dcompiler_43 d3dcompiler_47
        d3dx9 d3dx10 d3dx11_43 d3dxof
    )
    for verb in "${verbs[@]}"; do
        run_verb "$verb" || true
    done
}

apply_modern_vc() {
    if modern_vc_installed; then
        ok "Visual C++ 14.x is already registered for the prefix architecture."
        return 0
    fi
    if verb_installed vcrun2022; then
        warn "Winetricks records vcrun2022, but the required 14.x registry entries are incomplete."
        warn "The pack will not use --force. Review this prefix or use a dedicated clean prefix."
        FAILURES=$((FAILURES + 1))
        return 1
    fi
    run_verb vcrun2022 || true
}

apply_gaming_verbs() {
    run_verb xact || true
    if [[ "$(prefix_architecture)" == "win64" ]]; then
        warn "xact_x64 can help some games and break others; the prefix backup is available."
        run_verb xact_x64 || true
    else
        info "xact_x64 skipped on a win32 prefix."
    fi
    run_verb xinput || true
}

vulkan_ready() {
    [[ "${ARCHMIND_TEST_SIMULATE:-0}" == "1" ]] && return 0
    has vulkaninfo && vulkaninfo --summary >/dev/null 2>&1
}

show_plan() {
    normalize_prefix || return 1
    cat <<EOF
ArchMind Wine Compatibility Pack

Selected prefix ..... $PREFIX
Safety copy root .... $BACKUP_ROOT
Logs ................ $LOG_ROOT

Recommended pack:
  Core Fonts
  Visual C++ 2005, 2008, 2010, 2012 and 2013
  Visual C++ 14.x / 2015-2022 only when not already registered
  D3DCompiler 43/47, D3DX 9/10/11_43 and D3DXOF
  XACT, XACT x64 where applicable, and XInput

Optional and never automatic:
  DXVK, Windows 7-Zip and .NET Framework 4.8

No Proton files, VKD3D-Proton DLLs, or --force operations are used.
EOF
}

show_status() {
    normalize_prefix || return 1
    local state="not initialized" architecture="—" vc14="—" count=0
    if prefix_ready; then
        state="ready"
        architecture="$(prefix_architecture)"
        load_installed_verbs_from_log
        count=${#INSTALLED_VERBS[@]}
        if verb_installed vcrun2022; then vc14="recorded by Winetricks"; else vc14="not recorded"; fi
    elif prefix_has_unknown_content; then
        state="unsafe/non-prefix content"
    fi
    printf 'ArchMind Wine Compatibility Pack\n\n'
    printf 'Prefix .............. %s\n' "$PREFIX"
    printf 'State ............... %s\n' "$state"
    printf 'Architecture ........ %s\n' "$architecture"
    printf 'Installed verbs ..... %s\n' "$count"
    printf 'Visual C++ 14.x ..... %s\n' "$vc14"
    printf 'Safety copies ....... %s\n' "$BACKUP_ROOT"
    printf 'Logs ................ %s\n' "$LOG_ROOT"
}

list_installed() {
    normalize_prefix || return 1
    prefix_ready || { fail "The selected prefix is not initialized."; return 1; }
    require_runtime_tools || return 1
    printf 'Installed Winetricks components in %s:\n\n' "$PREFIX"
    env WINEPREFIX="$PREFIX" WINETRICKS_GUI=none winetricks list-installed
}

install_base() {
    require_normal_user || return 1
    normalize_prefix || return 1
    has pacman || { fail "Pacman is required for the Arch Linux base installation."; return 1; }
    has sudo || { fail "sudo is required to install the Wine base packages."; return 1; }
    [[ -f "${ARCHMIND_TEST_ARCH_RELEASE:-/etc/arch-release}" || "${ARCHMIND_TEST_SIMULATE:-0}" == "1" ]] || {
        fail "This base installer supports Arch Linux and Arch derivatives only."
        return 1
    }
    if ! prefix_ready && prefix_has_unknown_content; then
        fail "The selected directory contains files but is not a valid Wine prefix."
        return 1
    fi
    printf 'Selected prefix: %s\n' "$PREFIX"
    confirm_action "Install Wine base packages and initialize/update this prefix?" || {
        warn "Cancelled. No package was installed."
        return 1
    }
    init_log install-base || return 1
    run_logged "Installing Wine base packages" \
        sudo pacman -S --needed -- wine wine-mono wine-gecko winetricks cabextract unzip 7zip || return 1
    require_runtime_tools || return 1
    PREFIX_WAS_READY=0
    if prefix_ready; then
        PREFIX_WAS_READY=1
        create_backup || return 1
    elif prefix_has_unknown_content; then
        fail "The selected directory contains files but is not a valid Wine prefix."
        return 1
    fi
    initialize_prefix || return 1
    finish_action install-base
}

run_group() {
    local group="$1"
    case "$group" in
        core)
            prepare_mutation core "Apply Core Fonts, legacy Visual C++ and DirectX components?" || return 1
            apply_core_verbs
            ;;
        modern-vc)
            prepare_mutation modern-vc "Install Visual C++ 2015-2022 only if 14.x is missing?" || return 1
            apply_modern_vc
            ;;
        gaming)
            prepare_mutation gaming "Apply XACT, XAudio and XInput compatibility components?" || return 1
            apply_gaming_verbs
            ;;
        dxvk)
            vulkan_ready || { fail "Vulkan is not working; DXVK was not installed."; return 1; }
            prepare_mutation dxvk "Install optional DXVK in this prefix?" || return 1
            run_verb dxvk || true
            ;;
        7zip)
            prepare_mutation 7zip "Install optional Windows 7-Zip in this prefix?" || return 1
            run_verb 7zip || true
            ;;
        recommended)
            prepare_mutation recommended "Apply the complete recommended compatibility pack?" || return 1
            apply_core_verbs
            apply_modern_vc
            apply_gaming_verbs
            ;;
        *) return 2 ;;
    esac
    finish_action "$group"
}

apply_dotnet48() {
    require_normal_user || return 1
    normalize_prefix || return 1
    printf '\nWARNING: dotnet48 heavily modifies the selected prefix.\n'
    printf 'Use a dedicated prefix whenever possible.\n'
    [[ -t 0 ]] || { fail "dotnet48 requires an interactive confirmation."; return 1; }
    local answer=""
    read -r -p 'Type DOTNET48 to continue: ' answer
    [[ "$answer" == "DOTNET48" ]] || { warn "Cancelled. The prefix was not modified."; return 1; }
    ASSUME_YES=1
    prepare_mutation dotnet48 "Apply dotnet48?" || return 1
    run_verb dotnet48 || true
    finish_action dotnet48
}

backup_only() {
    require_normal_user || return 1
    normalize_prefix || return 1
    prefix_ready || { fail "There is no valid prefix to back up."; return 1; }
    require_runtime_tools || return 1
    confirm_action "Stop Wine processes and create a safety copy?" || return 1
    init_log backup || return 1
    create_backup || return 1
    printf 'Safety copy: %s\n' "$BACKUP_CREATED"
}

choose_prefix() {
    local answer=""
    printf 'Current prefix: %s\n' "$PREFIX_INPUT"
    read -r -p 'New prefix path (Enter keeps current): ' answer
    [[ -z "$answer" ]] || PREFIX_INPUT="$answer"
    normalize_prefix && printf 'Selected prefix: %s\n' "$PREFIX"
}

menu() {
    require_normal_user || return 1
    while true; do
        printf '\033[2J\033[H'
        normalize_prefix || return 1
        cat <<EOF
ARCHMIND — WINE COMPATIBILITY PACK

Prefix: $PREFIX

 1) Status
 2) Show installation plan
 3) Install Wine base and initialize/update prefix
 4) Apply recommended compatibility pack
 5) Core Fonts + VC++ 2005-2013 + DirectX legacy
 6) Visual C++ 14.x / 2015-2022
 7) XACT / XAudio / XInput
 8) DXVK [optional, requires Vulkan]
 9) Windows 7-Zip [optional]
10) .NET Framework 4.8 [manual/high impact]
11) List installed Winetricks components
12) Create prefix safety copy
13) Change selected prefix

 0) Back
EOF
        local choice=""
        read -r -p $'\nChoice: ' choice
        case "$choice" in
            1) show_status ;;
            2) show_plan ;;
            3) install_base ;;
            4) run_group recommended ;;
            5) run_group core ;;
            6) run_group modern-vc ;;
            7) run_group gaming ;;
            8) run_group dxvk ;;
            9) run_group 7zip ;;
            10) apply_dotnet48 ;;
            11) list_installed ;;
            12) backup_only ;;
            13) choose_prefix ;;
            0) return 0 ;;
            *) warn "Invalid option." ;;
        esac
        printf '\nPress Enter to continue...'
        read -r
    done
}

main() {
    parse_args "$@" || return $?
    case "$ACTION" in
        menu) menu ;;
        status) show_status ;;
        plan) show_plan ;;
        install-base) install_base ;;
        recommended|core|modern-vc|gaming|dxvk|7zip) run_group "$ACTION" ;;
        dotnet48) apply_dotnet48 ;;
        backup) backup_only ;;
        list) list_installed ;;
        *) return 2 ;;
    esac
}

main "$@"
