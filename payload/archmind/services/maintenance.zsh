#!/usr/bin/env zsh

typeset -g ARCHMIND_MAINTENANCE_TOOLS="$ARCHMIND_ROOT/tools"

maintenance_python_available() {
    (( $+commands[python3] ))
}

maintenance_run_tool() {
    emulate -L zsh
    local tool="$1"
    shift
    maintenance_python_available || {
        print -u2 -- "Python 3 is required for Maintenance Center."
        return 1
    }
    [[ -f "$ARCHMIND_MAINTENANCE_TOOLS/$tool" ]] || {
        print -u2 -- "Maintenance tool not found: $tool"
        return 1
    }
    ARCHMIND_DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}" \
        ARCHMIND_BACKUP_DIR="${ARCHMIND_BACKUP_DIR:-$HOME/ArchMind/Backups}" \
        python3 -B "$ARCHMIND_MAINTENANCE_TOOLS/$tool" "$@"
}

maintenance_hardware() { maintenance_run_tool hardware-profile.py; }
maintenance_guardian() { maintenance_run_tool update-guardian.py; }
maintenance_tasks() { maintenance_run_tool pending-tasks.py --interactive; }
maintenance_tasks_view() { maintenance_run_tool pending-tasks.py; }
maintenance_profiles() { maintenance_run_tool operating-profiles.py --interactive; }
maintenance_profile_view() { maintenance_run_tool operating-profiles.py; }
maintenance_cleanup() { maintenance_run_tool cleanup-audit.py --interactive; }
maintenance_cleanup_view() { maintenance_run_tool cleanup-audit.py; }
maintenance_backups() { maintenance_run_tool backup-catalog.py --interactive; }
maintenance_backups_latest() { maintenance_run_tool backup-catalog.py --latest; }
maintenance_rollback() { maintenance_run_tool rollback-center.py --interactive; }
maintenance_rollback_view() { maintenance_run_tool rollback-center.py; }

maintenance_pending_count() {
    emulate -L zsh
    local output count critical
    output="$(maintenance_run_tool pending-tasks.py --summary 2>/dev/null)" || {
        print -r -- "Unavailable"
        return 1
    }
    read -r count critical <<< "$output"
    [[ "$count" == <-> ]] || count=0
    print -r -- "${count:-0}"
}

maintenance_current_profile() {
    emulate -L zsh
    local output
    output="$(maintenance_run_tool operating-profiles.py --json 2>/dev/null)" || {
        print -r -- "Normal"
        return 1
    }
    print -r -- "$output" | sed -n 's/^[[:space:]]*"label": "\([^"]*\)",*$/\1/p' | head -n 1
}

maintenance_monitor_interval() {
    emulate -L zsh
    local interval
    interval="$(maintenance_run_tool operating-profiles.py --interval 2>/dev/null)" || interval=1
    [[ "$interval" == <-> || "$interval" == <->.<-> ]] || interval=1
    print -r -- "$interval"
}

maintenance_capability() {
    emulate -L zsh
    maintenance_run_tool hardware-profile.py --capability "$1" >/dev/null 2>&1
}
