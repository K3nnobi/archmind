#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"
typeset -g ARCHMIND_ROOT="${AFI_ROOT:h:h}"

source "$AFI_ROOT/panel.zsh"

source "$ARCHMIND_ROOT/services/settings.zsh"
settings_load

source "$ARCHMIND_ROOT/services/backup.zsh"
source "$ARCHMIND_ROOT/services/manager.zsh"
source "$ARCHMIND_ROOT/services/monitor.zsh"
source "$ARCHMIND_ROOT/services/doctor.zsh"
source "$ARCHMIND_ROOT/services/ai.zsh"
source "$ARCHMIND_ROOT/services/python.zsh"
source "$ARCHMIND_ROOT/services/packages.zsh"
source "$ARCHMIND_ROOT/services/maintenance.zsh"

afi_status_panel() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local selected="${1:-System}"
    local width="${2:-45%}"
    local height="${3:-14}"

    local latest=""
    local backup_count=0
    local latest_name="None"
    local latest_size="—"
    local manager_state="Unavailable"

    local cpu_usage="Unavailable"
    local memory_usage="Unavailable"
    local load_average="Unavailable"
    local failed_count=0

    local -a status_lines
    status_lines=()

    case "$selected" in
        "Backup Center")
            if manager_is_available; then
                manager_state="Available"
            fi

            backup_count="$(
                backup_find_files |
                    sed '/^$/d' |
                    wc -l |
                    tr -d ' '
            )"

            [[ "$backup_count" == <-> ]] || backup_count=0

            if latest="$(backup_get_latest 2>/dev/null)"; then
                latest_name="${latest:t}"
                latest_size="$(backup_human_size "$latest")"
            fi

            status_lines=(
                "Manager ........... ${manager_state}"
                "Backups ........... ${backup_count}"
                "Latest ............ ${latest_name}"
                "Size .............. ${latest_size}"
                ""
                "Safe Mode ......... Enabled"
            )
            ;;

        "Package Center")
            local package_total=0
            local foreign_total=0
            local orphan_total=0
            local flatpak_total=0
            local aur_helper="None"

            package_total="$(packages_pacman_count)" || true
            foreign_total="$(packages_foreign_count)" || true
            orphan_total="$(packages_orphan_count)" || true
            flatpak_total="$(packages_flatpak_count)" || true
            aur_helper="$(packages_aur_helper)" || true

            status_lines=(
                "Packages .......... ${package_total}"
                "AUR/Foreign ....... ${foreign_total}"
                "Orphans ........... ${orphan_total}"
                "Flatpaks .......... ${flatpak_total}"
                "AUR Helper ........ ${aur_helper}"
                ""
                "Safe Mode ......... Enabled"
            )
            ;;

        "System Monitor")
            cpu_usage="$(monitor_cpu_usage)"
            memory_usage="$(monitor_memory_usage)"
            load_average="$(monitor_load_average)"
            failed_count="$(monitor_failed_services_count)"

            status_lines=(
                "CPU ............... ${cpu_usage}"
                "Memory ............ ${memory_usage}"
                "Load Average ...... ${load_average}"
                ""
                "Failed Services ... ${failed_count}"
                "Refresh ........... On navigation"
            )
            ;;

        "AI Center")
            local ollama_state="Not installed"
            local api_state="Offline"
            local model_total=0
            local default_model="None"

            if ai_ollama_installed; then
                ollama_state="$(ai_ollama_service_state)" || true
                api_state="$(ai_ollama_api_state)" || true
                model_total="$(ai_model_count)"
                default_model="$(ai_resolve_default_model)" || true
            fi

            status_lines=(
                "Ollama ............ ${ollama_state}"
                "Local API ......... ${api_state}"
                "Models ............ ${model_total}"
                "Default ........... ${default_model}"
                ""
                "Backend ........... Local"
            )
            ;;

        "Python Center")
            local python_binary="Missing"
            local python_version="Not installed"
            local active_environment="None"
            local project_name="—"

            if python_binary="$(python_service_binary 2>/dev/null)"; then
                python_version="$(python_service_version)"
                active_environment="$(python_service_active_venv)" || true
            fi

            project_name="$(python_service_project)"

            status_lines=(
                "Python ............ ${python_version}"
                "Executable ........ ${python_binary}"
                "Environment ....... ${active_environment:t}"
                "Project ........... ${project_name:t}"
                ""
                "Status ............ Ready"
            )
            ;;

        "System Settings")
            settings_load

            status_lines=(
                "File .............. ${ARCHMIND_SETTINGS_FILE:t}"
                "Margin ............ ${ARCHMIND_CONSOLE_MARGIN}"
                "Confirmations ..... ${ARCHMIND_SAFE_CONFIRMATIONS}"
                ""
                "Persistence ....... Enabled"
                "Status ............ Ready"
            )
            ;;

        "Maintenance Center")
            local pending_total="Unavailable"
            local operating_profile="Normal"
            pending_total="$(maintenance_pending_count)" || true
            operating_profile="$(maintenance_current_profile)" || true
            [[ -n "$operating_profile" ]] || operating_profile="Normal"

            status_lines=(
                "Pending tasks ..... ${pending_total}"
                "Profile ........... ${operating_profile}"
                "Cleanup ........... Review first"
                "Rollback .......... Registered only"
                "Guardian .......... On demand/update"
                "Hardware .......... Auto detected"
            )
            ;;

        "ArchMind Doctor")
            status_lines=(
                "Last session result:"
                "${DOCTOR_LAST_RESULT:-Not run}"
                ""
                "Reports ........... Logs/Doctor"
                "View Report ....... Read only"
                "Checks run only when selected."
            )
            ;;

        "System"|*)
            local home_pending="0"
            home_pending="$(maintenance_pending_count)" || home_pending="Unavailable"
            status_lines=(
                "Interface ......... Online"
                "AFI Engine ........ Active"
                "System ............ Arch Linux"
                "Shell ............. Zsh"
                "Pending tasks ..... ${home_pending}"
                "Status ............ Ready"
            )
            ;;
    esac

    afi_panel \
        --title "System Status" \
        --width "$width" \
        --height "$height" \
        --padding 2 \
        "${status_lines[@]}"
}
