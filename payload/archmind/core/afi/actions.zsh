#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"
typeset -g ARCHMIND_ROOT="${AFI_ROOT:h:h}"

source "$ARCHMIND_ROOT/services/settings.zsh"
settings_load

source "$AFI_ROOT/viewer.zsh"
source "$AFI_ROOT/dialog.zsh"
source "$AFI_ROOT/notification.zsh"
source "$AFI_ROOT/external.zsh"

source "$ARCHMIND_ROOT/services/system.zsh"
source "$ARCHMIND_ROOT/services/backup.zsh"
source "$ARCHMIND_ROOT/services/manager.zsh"
source "$ARCHMIND_ROOT/services/monitor.zsh"
source "$ARCHMIND_ROOT/services/doctor.zsh"
source "$ARCHMIND_ROOT/services/ai.zsh"
source "$ARCHMIND_ROOT/services/python.zsh"
source "$ARCHMIND_ROOT/services/packages.zsh"
source "$ARCHMIND_ROOT/services/maintenance.zsh"

afi_open_manager() {
    emulate -L zsh
    setopt localoptions typesetsilent

    if ! manager_is_available; then
        afi_notification \
            error \
            "Manager Not Found" \
            "The ArchMind Manager script was not found." \
            62
        return 1
    fi

    if ! afi_confirm_dialog \
        "Open ArchMind Manager" \
        "The console will be suspended while the classic manager is open." \
        72; then
        return 0
    fi

    afi_run_external manager_run
}

afi_organize_home_zsh() {
    bash "$ARCHMIND_ROOT/tools/organize-home-zsh.sh" --offer
}

afi_python_tool() {
    emulate -L zsh
    local tool="$1"
    shift
    (( $+commands[python3] )) || {
        print -r -- "Python 3.10+ is required for this feature (Arch package: python)."
        return 1
    }
    ARCHMIND_DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}" \
        python3 -B "$ARCHMIND_ROOT/tools/$tool" "$@"
}

afi_live_monitor() {
    local interval
    interval="$(maintenance_monitor_interval 2>/dev/null)" || interval=1
    afi_python_tool live-monitor.py --interval "$interval"
}
afi_system_updates() { afi_python_tool system-updates.py --interactive; }
afi_check_updates() { afi_python_tool system-updates.py; }

afi_dispatch_action() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local action="${1:-}"
    local label="${2:-Option}"

    case "$action" in
        system-info)
            system_collect_information

            afi_viewer \
                "System Information" \
                "${SYSTEM_INFORMATION_LINES[@]}"
            ;;

        services)
            local services_output=""

            services_output="$(
                systemctl --failed --no-legend 2>/dev/null \
                    | head -n 10
            )"

            [[ -n "$services_output" ]] || \
                services_output="No failed services found."

            afi_viewer \
                "System Services" \
                "Services currently in a failed state:" \
                "" \
                "$services_output"
            ;;

        storage)
            local disk_output=""
            disk_output="$(afi_python_tool storage-info.py 2>&1)" || true
            afi_viewer "Storage" "$disk_output"
            ;;

        maintenance-hardware)
            local hardware_output=""
            hardware_output="$(maintenance_hardware 2>&1)" || true
            afi_viewer "Hardware Profile" "$hardware_output"
            ;;

        maintenance-guardian)
            afi_run_external maintenance_guardian
            ;;

        maintenance-tasks)
            afi_run_external maintenance_tasks
            ;;

        maintenance-rollback)
            afi_run_external maintenance_rollback
            ;;

        maintenance-cleanup)
            afi_run_external maintenance_cleanup
            ;;

        maintenance-backups)
            afi_run_external maintenance_backups
            ;;

        maintenance-profiles)
            afi_run_external maintenance_profiles
            ;;

        backup-info)
            backup_collect_summary

            afi_viewer \
                "Backup Summary" \
                "${BACKUP_SUMMARY_LINES[@]}"
            ;;

        backup-list)
            backup_list_information

            afi_viewer \
                "Available Backups" \
                "${BACKUP_LIST_LINES[@]}"
            ;;

        verify)
            backup_validate_latest || true

            afi_viewer \
                "Backup Validation" \
                "${BACKUP_VALIDATION_LINES[@]}"
            ;;

        backup-manifest)
            backup_read_manifest || true

            afi_viewer \
                "Backup Manifest" \
                "${BACKUP_MANIFEST_LINES[@]}"
            ;;

        backup-full|backup-partial|restore|manager-open)
            afi_open_manager
            ;;

        updates)
            afi_run_external afi_system_updates
            ;;

        monitor-live)
            afi_run_external afi_live_monitor
            ;;

        monitor-overview)
            monitor_collect_overview

            afi_viewer \
                "System Overview" \
                "${MONITOR_OVERVIEW_LINES[@]}"
            ;;

        processes)
            monitor_collect_processes

            afi_viewer \
                "Processes" \
                "${MONITOR_PROCESS_LINES[@]}"
            ;;

        temperatures)
            monitor_collect_temperatures

            afi_viewer \
                "Temperatures" \
                "${MONITOR_TEMPERATURE_LINES[@]}"
            ;;

        monitor-services)
            monitor_collect_failed_services

            afi_viewer \
                "Failed Services" \
                "${MONITOR_SERVICE_LINES[@]}"
            ;;

        doctor-quick)
            doctor_collect_quick
            doctor_record_report Quick "${DOCTOR_QUICK_LINES[@]}" || true

            afi_viewer \
                "Quick Diagnosis" \
                "${DOCTOR_QUICK_LINES[@]}" "" "$DOCTOR_REPORT_NOTE"
            ;;

        doctor-full)
            doctor_collect_full
            doctor_record_report Full "${DOCTOR_FULL_LINES[@]}" || true

            afi_viewer \
                "Full Diagnosis" \
                "${DOCTOR_FULL_LINES[@]}" "" "$DOCTOR_REPORT_NOTE"
            ;;

        doctor-pacman)
            doctor_collect_pacman
            doctor_record_report Pacman "${DOCTOR_PACMAN_LINES[@]}" || true

            afi_viewer \
                "Pacman Diagnosis" \
                "${DOCTOR_PACMAN_LINES[@]}" "" "$DOCTOR_REPORT_NOTE"
            ;;

        doctor-audio)
            doctor_collect_audio
            doctor_record_report Audio "${DOCTOR_AUDIO_LINES[@]}" || true

            afi_viewer \
                "Audio Diagnosis" \
                "${DOCTOR_AUDIO_LINES[@]}" "" "$DOCTOR_REPORT_NOTE"
            ;;

        doctor-report)
            local report_output
            report_output="$(doctor_view_report 2>&1)" || true
            afi_viewer "Doctor Report" "$report_output"
            ;;

        ai-status)
            ai_collect_status

            afi_viewer \
                "Ollama Status" \
                "${AI_STATUS_LINES[@]}"
            ;;

        ai-models)
            ai_collect_models || true

            afi_viewer \
                "Installed Models" \
                "${AI_MODEL_LINES[@]}"
            ;;

        ai-running)
            ai_collect_running_models || true

            afi_viewer \
                "Loaded Models" \
                "${AI_RUNNING_LINES[@]}"
            ;;

        ai-chat)
            if ! ai_ollama_installed; then
                afi_notification \
                    error \
                    "Ollama Not Available" \
                    "Ollama executable was not found." \
                    64
            elif [[ "$(ai_ollama_api_state)" != "Online" ]]; then
                afi_notification \
                    warning \
                    "Ollama Offline" \
                    "The local Ollama API is not responding." \
                    64
            elif ! ai_resolve_default_model >/dev/null 2>&1; then
                afi_notification \
                    warning \
                    "Missing Model" \
                    "No local model was found." \
                    64
            elif afi_confirm_dialog \
                "Open Local Assistant" \
                "The console will be temporarily suspended while the local assistant is running." \
                68; then
                afi_run_external ai_run_chat
            fi
            ;;

        ai-settings)
            afi_viewer \
                "AI Configuration" \
                "Preferred model:" \
                "${ARCHMIND_AI_MODEL}" \
                "" \
                "To change temporarily:" \
                "export ARCHMIND_AI_MODEL=\"model-name\""
            ;;

        python-info)
            python_collect_information

            afi_viewer \
                "Python Information" \
                "${PYTHON_INFORMATION_LINES[@]}"
            ;;

        python-environments)
            python_collect_environments

            afi_viewer \
                "Virtual Environments" \
                "${PYTHON_ENVIRONMENT_LINES[@]}"
            ;;

        python-packages)
            python_collect_packages || true

            afi_viewer \
                "Python Packages" \
                "${PYTHON_PACKAGE_LINES[@]}"
            ;;

        python-venv)
            if afi_confirm_dialog \
                "Create Virtual Environment" \
                "A .venv directory will be created inside the configured project." \
                68; then
                afi_run_external python_create_venv
            fi
            ;;

        python-activate)
            local activation_output=""

            activation_output="$(python_show_activation_command 2>&1)" || true

            afi_viewer \
                "Activate Environment" \
                "$activation_output"
            ;;

        python-settings)
            afi_viewer \
                "Python Configuration" \
                "Configured project:" \
                "${ARCHMIND_PYTHON_PROJECT}" \
                "" \
                "To change before opening the console:" \
                "export ARCHMIND_PYTHON_PROJECT=/path/to/project"
            ;;

        organize-home-zsh)
            afi_run_external afi_organize_home_zsh
            ;;

        settings-info)
            settings_collect_information

            afi_viewer \
                "Current Settings" \
                "${SETTINGS_INFORMATION_LINES[@]}"
            ;;

        settings-ai-model)
            afi_suspend_console

            if settings_set_ai_model; then
                print
                print -r -- "Model updated successfully."
            else
                print
                print -r -- "No changes made."
            fi

            print
            print -r -- "Press Enter to return..."
            read -r
            afi_resume_console
            ;;

        settings-backup-dir)
            afi_suspend_console

            if settings_set_backup_dir; then
                print
                print -r -- "Backup directory updated."
            else
                print
                print -r -- "No changes made."
            fi

            print
            print -r -- "Press Enter to return..."
            read -r
            afi_resume_console
            ;;

        settings-python-project)
            afi_suspend_console

            if settings_set_python_project; then
                print
                print -r -- "Python project updated."
            else
                print
                print -r -- "No changes made."
            fi

            print
            print -r -- "Press Enter to return..."
            read -r
            afi_resume_console
            ;;

        settings-margin)
            afi_suspend_console

            if settings_set_margin; then
                print
                print -r -- "Margin updated."
            else
                print
                print -r -- "No changes made."
            fi

            print
            print -r -- "Press Enter to return..."
            read -r
            afi_resume_console
            ;;

        settings-confirmations)
            afi_suspend_console
            settings_toggle_confirmations

            print
            print -r -- "Press Enter to return..."
            read -r
            afi_resume_console
            ;;

        settings-reset)
            if afi_confirm_dialog \
                "Restore Settings" \
                "Restore all ArchMind preferences to their default values?" \
                72; then
                settings_restore_defaults

                afi_notification \
                    success \
                    "Settings Restored" \
                    "Default settings have been restored." \
                    64
            fi
            ;;

        packages-summary)
            packages_collect_summary

            afi_viewer \
                "Package Summary" \
                "${PACKAGE_SUMMARY_LINES[@]}"
            ;;

        packages-updates)
            afi_run_external afi_check_updates
            ;;

        packages-orphans)
            packages_collect_orphans

            afi_viewer \
                "Orphan Packages" \
                "${PACKAGE_ORPHAN_LINES[@]}"
            ;;

        packages-foreign)
            packages_collect_foreign

            afi_viewer \
                "Foreign & AUR Packages" \
                "${PACKAGE_FOREIGN_LINES[@]}"
            ;;

        packages-profiles)
            packages_collect_profiles

            afi_viewer \
                "Installation Profiles" \
                "${PACKAGE_PROFILE_LINES[@]}"
            ;;

        nautilus-configure)
            if afi_confirm_dialog \
                "Configure Nautilus" \
                "Install dependencies and enable embedded icons for .exe thumbnails?" \
                74; then
                afi_run_external manager_configure_nautilus
            fi
            ;;

        gnome-appearance-configure)
            if afi_confirm_dialog \
                "Configure GNOME Appearance" \
                "Install rounded blur and set Papirus-Dark folders to yellow?" \
                74; then
                afi_run_external manager_configure_gnome_appearance
            fi
            ;;

        gamemode-blur-configure)
            afi_run_external manager_configure_gamemode_blur
            ;;

        gnome-drag-hover-configure)
            afi_run_external manager_configure_gnome_drag_hover
            ;;

        wine-compatibility-configure)
            afi_run_external manager_configure_wine_compatibility
            ;;

        capslock-nodelay-configure)
            afi_run_external manager_configure_capslock_nodelay
            ;;

        firefox-chatgpt-emoji-configure)
            afi_run_external manager_configure_firefox_chatgpt_emoji
            ;;

        nvibrant-configure)
            afi_run_external manager_configure_nvibrant
            ;;

        plymouth-patch-configure)
            afi_run_external manager_configure_plymouth_patch
            ;;

        install-base|install-terminal|install-gaming|install-audio|install-dev)
            afi_open_manager
            ;;

        packages-manager)
            afi_open_manager
            ;;


        *)
            afi_notification \
                info \
                "Module in Development" \
                "${label} is not implemented yet." \
                66
            ;;
    esac
}
