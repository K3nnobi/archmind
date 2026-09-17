#!/usr/bin/env zsh
# Read-only checks. Missing commands and query failures are never Healthy.

doctor_check_internet() {
    emulate -L zsh
    (( $+commands[ping] )) || { print -r -- "Unavailable (ping missing)"; return 1; }
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && { print -r -- "OK"; return 0; }
    print -r -- "Failed (ICMP may be blocked)"
    return 1
}

doctor_check_dns() {
    emulate -L zsh
    (( $+commands[timeout] && $+commands[getent] )) || {
        print -r -- "Unavailable (DNS tools missing)"; return 1
    }
    timeout 8 getent hosts archlinux.org >/dev/null 2>&1 && { print -r -- "OK"; return 0; }
    print -r -- "Failed or timed out"
    return 1
}

doctor_check_pacman_lock() {
    emulate -L zsh
    (( $+commands[pacman] )) || { print -r -- "Unavailable (Pacman missing)"; return 1; }
    [[ -e /var/lib/pacman/db.lck ]] && { print -r -- "Locked"; return 1; }
    print -r -- "OK"
}

doctor_check_pacman_database() {
    emulate -L zsh
    (( $+commands[pacman] )) || { print -r -- "Unavailable (Pacman missing)"; return 1; }
    LC_ALL=C pacman -Dk >/dev/null 2>&1 && { print -r -- "OK"; return 0; }
    print -r -- "Failed (local database check)"
    return 1
}

doctor_check_mirrorlist() {
    emulate -L zsh
    local count
    [[ -r /etc/pacman.d/mirrorlist ]] || { print -r -- "Unavailable (mirrorlist unreadable)"; return 1; }
    count="$(grep -Ec '^[[:space:]]*Server[[:space:]]*=' /etc/pacman.d/mirrorlist 2>/dev/null)"
    [[ "$count" == <-> ]] && (( count > 0 )) && { print -r -- "OK ($count servers)"; return 0; }
    print -r -- "Failed (no enabled mirror servers)"
    return 1
}

doctor_check_disk() {
    emulate -L zsh
    local output usage
    output="$(LC_ALL=C df -P / 2>/dev/null)" || { print -r -- "Unavailable"; return 1; }
    usage="$(print -r -- "$output" | awk 'NR == 2 {gsub("%", "", $5); print $5}')"
    [[ "$usage" == <-> ]] || { print -r -- "Unavailable"; return 1; }
    if (( usage >= 90 )); then
        print -r -- "Critical ($usage%)"; return 1
    elif (( usage >= 80 )); then
        print -r -- "Warning ($usage%)"; return 1
    fi
    print -r -- "OK ($usage%)"
}

doctor_check_failed_services() {
    emulate -L zsh
    local output count
    (( $+commands[systemctl] )) || { print -r -- "Unavailable (systemctl missing)"; return 1; }
    output="$(LC_ALL=C systemctl --failed --no-legend --no-pager --plain 2>/dev/null)" || {
        print -r -- "Unavailable (systemd query failed)"; return 1
    }
    count="$(print -r -- "$output" | awk 'NF {n++} END {print n+0}')"
    (( count == 0 )) && { print -r -- "OK"; return 0; }
    print -r -- "$count failed service(s)"
    return 1
}

doctor_service_state() {
    emulate -L zsh
    local output result
    (( $+commands[systemctl] )) || { print -r -- "Unavailable"; return 1; }
    output="$(LC_ALL=C systemctl --user is-active "$1" 2>/dev/null)"
    result=$?
    if (( result == 0 )) && [[ "$output" == active ]]; then
        print -r -- "Active"; return 0
    fi
    case "$output" in
        inactive|failed|unknown) print -r -- "$output" ;;
        *) print -r -- "Unavailable (user service query failed)" ;;
    esac
    return 1
}

doctor_check_pipewire() { doctor_service_state pipewire.service; }

doctor_check_plymouth_patch() {
    emulate -L zsh
    local state="$HOME/ArchMind/Config/Patches/Plymouth/state.conf"
    local helper="$ARCHMIND_ROOT/patches/plymouth/plymouth-patch.sh"
    [[ -f "$state" ]] || { print -r -- "Not configured (optional)"; return 0; }
    [[ -x "$helper" && -f "$helper" && ! -L "$helper" ]] || {
        print -r -- "Unavailable (patch helper missing)"
        return 1
    }
    if bash "$helper" --check >/dev/null 2>&1; then
        print -r -- "OK"
        return 0
    fi
    print -r -- "Needs reapply"
    return 1
}

doctor_check_maintenance_tasks() {
    emulate -L zsh
    local helper="$ARCHMIND_ROOT/tools/pending-tasks.py"
    local output pending critical
    (( $+commands[python3] )) || { print -r -- "Unavailable (Python missing)"; return 1; }
    [[ -f "$helper" ]] || { print -r -- "Unavailable (task helper missing)"; return 1; }
    output="$(ARCHMIND_DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}" python3 -B "$helper" --summary 2>/dev/null)" || {
        print -r -- "Unavailable (task state failed)"
        return 1
    }
    read -r pending critical <<< "$output"
    [[ "$pending" == <-> && "$critical" == <-> ]] || {
        print -r -- "Unavailable (invalid task summary)"
        return 1
    }
    if (( critical > 0 )); then
        print -r -- "$pending pending ($critical critical)"
        return 1
    fi
    print -r -- "$pending pending"
    return 0
}

doctor_check_wine_compatibility() {
    emulate -L zsh
    setopt localoptions nullglob
    local -a receipts
    local helper="$ARCHMIND_ROOT/tools/configure-wine-compatibility.sh"
    receipts=("${ARCHMIND_DATA_HOME:-$HOME/ArchMind}"/Config/Wine/prefix-*.conf(N))
    (( ${#receipts[@]} > 0 )) || {
        print -r -- "Not configured (optional)"
        return 0
    }
    [[ -x "$helper" && -f "$helper" && ! -L "$helper" ]] || {
        print -r -- "Unavailable (Wine pack helper missing)"
        return 1
    }
    print -r -- "${#receipts[@]} recorded prefix(es); review on demand"
}

doctor_check_gnome_drag_hover() {
    emulate -L zsh
    local backups="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}/Installer-Backups/GNOME-Drag-Hover"
    local helper="$ARCHMIND_ROOT/tools/configure-gnome-drag-hover.py"
    [[ -d "$backups" ]] || { print -r -- "Not configured (optional)"; return 0; }
    (( $+commands[python3] )) || { print -r -- "Unavailable (Python missing)"; return 1; }
    [[ -x "$helper" && -f "$helper" && ! -L "$helper" ]] || {
        print -r -- "Unavailable (Drag Hover helper missing)"
        return 1
    }
    if python3 -B "$helper" --check >/dev/null 2>&1; then
        print -r -- "OK"
        return 0
    fi
    print -r -- "Needs reapply or manual review"
    return 1
}

doctor_package_count() {
    emulate -L zsh
    local output result
    (( $+commands[pacman] )) || { print -r -- "Unavailable"; return 1; }
    output="$(LC_ALL=C pacman "$1" 2>&1)"
    result=$?
    if (( result == 0 )); then
        print -r -- "$output" | awk 'NF {n++} END {print n+0}'
        return 0
    fi
    if [[ "$1" == -Qtdq && -z "$output" ]] && (( result == 1 )); then
        print -r -- "0"; return 0
    fi
    print -r -- "Unavailable (Pacman query failed)"
    return 1
}

doctor_collect_quick() {
    emulate -L zsh
    setopt localoptions typesetsilent
    typeset -ga DOCTOR_QUICK_LINES
    typeset -g DOCTOR_LAST_RESULT
    typeset -gi DOCTOR_WARNINGS=0
    local internet dns lock database mirrors disk services
    internet="$(doctor_check_internet)" || (( DOCTOR_WARNINGS++ ))
    dns="$(doctor_check_dns)" || (( DOCTOR_WARNINGS++ ))
    lock="$(doctor_check_pacman_lock)" || (( DOCTOR_WARNINGS++ ))
    database="$(doctor_check_pacman_database)" || (( DOCTOR_WARNINGS++ ))
    mirrors="$(doctor_check_mirrorlist)" || (( DOCTOR_WARNINGS++ ))
    disk="$(doctor_check_disk)" || (( DOCTOR_WARNINGS++ ))
    services="$(doctor_check_failed_services)" || (( DOCTOR_WARNINGS++ ))
    DOCTOR_LAST_RESULT="Healthy"
    (( DOCTOR_WARNINGS )) && DOCTOR_LAST_RESULT="$DOCTOR_WARNINGS warning(s) / unavailable check(s)"
    DOCTOR_QUICK_LINES=(
        "Internet ........... $internet"
        "DNS ................ $dns"
        "Pacman lock ........ $lock"
        "Local database ..... $database"
        "Mirrorlist ......... $mirrors"
        "Root filesystem .... $disk"
        "Failed services .... $services"
        ""
        "Result ............. $DOCTOR_LAST_RESULT"
    )
}

doctor_collect_full() {
    emulate -L zsh
    setopt localoptions typesetsilent
    typeset -ga DOCTOR_FULL_LINES
    doctor_collect_quick
    local pipewire kernel uptime_value orphans plymouth_patch maintenance_tasks wine_pack drag_hover
    pipewire="$(doctor_check_pipewire)" || (( DOCTOR_WARNINGS++ ))
    kernel="$(uname -r 2>/dev/null)" || { kernel="Unavailable"; (( DOCTOR_WARNINGS++ )); }
    uptime_value="$(LC_ALL=C uptime -p 2>/dev/null)" || { uptime_value="Unavailable"; (( DOCTOR_WARNINGS++ )); }
    orphans="$(doctor_package_count -Qtdq)" || (( DOCTOR_WARNINGS++ ))
    plymouth_patch="$(doctor_check_plymouth_patch)" || (( DOCTOR_WARNINGS++ ))
    maintenance_tasks="$(doctor_check_maintenance_tasks)" || (( DOCTOR_WARNINGS++ ))
    wine_pack="$(doctor_check_wine_compatibility)" || (( DOCTOR_WARNINGS++ ))
    drag_hover="$(doctor_check_gnome_drag_hover)" || (( DOCTOR_WARNINGS++ ))
    DOCTOR_LAST_RESULT="Healthy"
    (( DOCTOR_WARNINGS )) && DOCTOR_LAST_RESULT="$DOCTOR_WARNINGS warning(s) / unavailable check(s)"
    DOCTOR_FULL_LINES=(
        "${(@)DOCTOR_QUICK_LINES[1,-3]}"
        "Kernel ............. $kernel"
        "Uptime ............. $uptime_value"
        "PipeWire ........... $pipewire"
        "Orphan packages .... $orphans"
        "Plymouth patch ..... $plymouth_patch"
        "Maintenance tasks . $maintenance_tasks"
        "Wine pack .......... $wine_pack"
        "GNOME Drag Hover .. $drag_hover"
        ""
        "Result ............. $DOCTOR_LAST_RESULT"
        "Orphans are informational; no packages were removed."
    )
}

doctor_collect_pacman() {
    emulate -L zsh
    setopt localoptions typesetsilent
    typeset -ga DOCTOR_PACMAN_LINES
    local lock database mirrors total orphans
    lock="$(doctor_check_pacman_lock)" || true
    database="$(doctor_check_pacman_database)" || true
    mirrors="$(doctor_check_mirrorlist)" || true
    total="$(doctor_package_count -Qq)" || true
    orphans="$(doctor_package_count -Qtdq)" || true
    DOCTOR_PACMAN_LINES=(
        "Executable ......... ${commands[pacman]:-Unavailable}"
        "Lock ............... $lock"
        "Local database ..... $database"
        "Mirrorlist ......... $mirrors"
        "Installed packages . $total"
        "Orphan packages .... $orphans"
    )
}

doctor_collect_audio() {
    emulate -L zsh
    setopt localoptions typesetsilent
    typeset -ga DOCTOR_AUDIO_LINES
    local pipewire wireplumber pulse sinks="Unavailable (wpctl missing)" output
    pipewire="$(doctor_service_state pipewire.service)" || true
    wireplumber="$(doctor_service_state wireplumber.service)" || true
    pulse="$(doctor_service_state pipewire-pulse.service)" || true
    if (( $+commands[wpctl] )); then
        if output="$(LC_ALL=C wpctl status 2>/dev/null)"; then
            sinks="$(print -r -- "$output" | grep -A 12 'Sinks:' | head -n 8)"
            [[ -n "$sinks" ]] || sinks="No outputs detected."
        else
            sinks="Unavailable (audio query failed)"
        fi
    fi
    DOCTOR_AUDIO_LINES=(
        "PipeWire ........... $pipewire"
        "WirePlumber ........ $wireplumber"
        "PipeWire Pulse ..... $pulse"
        ""
        "Detected outputs:"
        "$sinks"
    )
}

doctor_record_report() {
    emulate -L zsh
    setopt localoptions typesetsilent
    local kind="$1"
    shift
    typeset -g DOCTOR_REPORT_NOTE
    if ! (( $+commands[python3] )); then
        DOCTOR_REPORT_NOTE="Report not saved: Python 3 is unavailable."
        return 1
    fi
    DOCTOR_REPORT_NOTE="$(print -rl -- "$@" |
        ARCHMIND_DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}" python3 -B \
        "$ARCHMIND_ROOT/tools/doctor-report.py" --save "$kind" --version "1.5.18" 2>&1)"
}

doctor_view_report() {
    emulate -L zsh
    (( $+commands[python3] )) || { print -r -- "Python 3 is required to read saved reports."; return 1; }
    ARCHMIND_DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}" python3 -B "$ARCHMIND_ROOT/tools/doctor-report.py"
}
