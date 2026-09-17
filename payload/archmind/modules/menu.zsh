# ==========================================
# ArchMind Interactive Menu
# Intelligence meets Linux
# ==========================================

_archmind_menu_pause() {
    if [[ "${ARCHMIND_MENU_PAUSE:-true}" != "true" ]]; then
        return 0
    fi

    echo
    read -rk 1 "?Press any key to continue..."
}

_archmind_menu_header() {
    if [[ "${ARCHMIND_MENU_CLEAR:-true}" == "true" ]]; then
        clear
    fi

    _archmind_ui_header \
        "ARCHMIND" \
        "Intelligence meets Linux"

    printf "  Version %s" "${ARCHMIND_VERSION:-0.2.0}"
    printf "  •  %s\n" "${ARCHMIND_CODENAME:-Cyber Interface}"

    echo
}

_archmind_menu_system() {
    while true; do
        _archmind_menu_header

        print -P "%F{cyan}%BSYSTEM%b%f"
        echo
        echo "  1) Machine summary"
        echo "  2) Quick status"
        echo "  3) Memory"
        echo "  4) Disks"
        echo "  5) Battery"
        echo "  6) Updates"
        echo
        echo "  0) Back"
        echo

        local choice
        read "choice?Choice: "

        case "$choice" in
            1)
                archmind_system
                _archmind_menu_pause
                ;;
            2)
                archmind_status
                _archmind_menu_pause
                ;;
            3)
                archmind_memory
                _archmind_menu_pause
                ;;
            4)
                archmind_disk
                _archmind_menu_pause
                ;;
            5)
                archmind_battery
                _archmind_menu_pause
                ;;
            6)
                archmind_updates
                _archmind_menu_pause
                ;;
            0)
                return 0
                ;;
            *)
                _archmind_warn "Invalid option."
                sleep 1
                ;;
        esac
    done
}

_archmind_menu_monitor() {
    while true; do
        _archmind_menu_header

        print -P "%F{cyan}%BMONITORING%b%f"
        echo
        echo "  1) Live monitor"
        echo "  2) Temperatures"
        echo "  3) GPU"
        echo "  4) Processes by CPU"
        echo "  5) Processes by memory"
        echo
        echo "  0) Back"
        echo

        local choice
        read "choice?Choice: "

        case "$choice" in
            1)
                archmind_monitor
                ;;
            2)
                archmind_temperatures
                _archmind_menu_pause
                ;;
            3)
                archmind_gpu
                _archmind_menu_pause
                ;;
            4)
                archmind_processes
                _archmind_menu_pause
                ;;
            5)
                archmind_memory_processes
                _archmind_menu_pause
                ;;
            0)
                return 0
                ;;
            *)
                _archmind_warn "Invalid option."
                sleep 1
                ;;
        esac
    done
}

_archmind_menu_python() {
    while true; do
        _archmind_menu_header

        print -P "%F{cyan}%BPYTHON%b%f"
        echo
        echo "  1) Status"
        echo "  2) Create virtual environment"
        echo "  3) Activate virtual environment"
        echo "  4) Deactivate virtual environment"
        echo "  5) List packages"
        echo "  6) Install requirements.txt"
        echo "  7) Generate requirements.txt"
        echo "  8) Update pip"
        echo
        echo "  0) Back"
        echo

        local choice
        read "choice?Choice: "

        case "$choice" in
            1)
                archmind_python_status
                _archmind_menu_pause
                ;;
            2)
                local venv_name
                read "venv_name?Environment directory [${ARCHMIND_VENV_DIR:-.venv}]: "
                archmind_python_create "${venv_name:-${ARCHMIND_VENV_DIR:-.venv}}"
                _archmind_menu_pause
                ;;
            3)
                local venv_name
                read "venv_name?Environment directory [${ARCHMIND_VENV_DIR:-.venv}]: "
                archmind_python_activate "${venv_name:-${ARCHMIND_VENV_DIR:-.venv}}"
                _archmind_menu_pause
                ;;
            4)
                archmind_python_deactivate
                _archmind_menu_pause
                ;;
            5)
                archmind_python_list
                _archmind_menu_pause
                ;;
            6)
                local requirements
                read "requirements?File [requirements.txt]: "
                archmind_python_requirements "${requirements:-requirements.txt}"
                _archmind_menu_pause
                ;;
            7)
                local requirements
                read "requirements?File [requirements.txt]: "
                archmind_python_freeze "${requirements:-requirements.txt}"
                _archmind_menu_pause
                ;;
            8)
                archmind_python_upgrade_pip
                _archmind_menu_pause
                ;;
            0)
                return 0
                ;;
            *)
                _archmind_warn "Invalid option."
                sleep 1
                ;;
        esac
    done
}

_archmind_menu_git() {
    while true; do
        _archmind_menu_header

        print -P "%F{cyan}%BGIT%b%f"
        echo
        echo "  1) Status"
        echo "  2) History"
        echo "  3) Branches"
        echo "  4) Changes"
        echo "  5) Staged changes"
        echo "  6) Add changes"
        echo "  7) Create commit"
        echo "  8) Pull"
        echo "  9) Push"
        echo " 10) Synchronize"
        echo
        echo "  0) Back"
        echo

        local choice
        read "choice?Choice: "

        case "$choice" in
            1)
                archmind_git_status
                _archmind_menu_pause
                ;;
            2)
                archmind_git_log
                _archmind_menu_pause
                ;;
            3)
                archmind_git_branches
                _archmind_menu_pause
                ;;
            4)
                archmind_git_diff
                ;;
            5)
                archmind_git_diff_staged
                ;;
            6)
                archmind_git_add
                _archmind_menu_pause
                ;;
            7)
                local message
                read "message?Commit message: "

                if [[ -n "$message" ]]; then
                    archmind_git_commit "$message"
                else
                    _archmind_warn "The message cannot be empty."
                fi

                _archmind_menu_pause
                ;;
            8)
                archmind_git_pull
                _archmind_menu_pause
                ;;
            9)
                archmind_git_push
                _archmind_menu_pause
                ;;
            10)
                archmind_git_sync
                _archmind_menu_pause
                ;;
            0)
                return 0
                ;;
            *)
                _archmind_warn "Invalid option."
                sleep 1
                ;;
        esac
    done
}

_archmind_menu_ai() {
    while true; do
        _archmind_menu_header

        print -P "%F{cyan}%BLOCAL INTELLIGENCE%b%f"
        echo
        printf "  Default model: %s\n" "${ARCHMIND_AI_DEFAULT_MODEL:-qwen2.5-coder:7b}"
        echo
        echo "  1) Status"
        echo "  2) Chat with the default model"
        echo "  3) List models"
        echo "  4) Running models"
        echo "  5) Download model"
        echo "  6) Remove model"
        echo "  7) Set default model"
        echo "  8) Check GPU"
        echo "  9) Start Ollama"
        echo " 10) Stop Ollama service"
        echo
        echo "  0) Back"
        echo

        local choice
        read "choice?Choice: "

        case "$choice" in
            1)
                archmind_ai_status
                _archmind_menu_pause
                ;;
            2)
                archmind_ai_run "${ARCHMIND_AI_DEFAULT_MODEL:-qwen2.5-coder:7b}"
                ;;
            3)
                archmind_ai_list
                _archmind_menu_pause
                ;;
            4)
                archmind_ai_running
                _archmind_menu_pause
                ;;
            5)
                local model
                read "model?Model [${ARCHMIND_AI_DEFAULT_MODEL:-qwen2.5-coder:7b}]: "
                archmind_ai_pull "${model:-${ARCHMIND_AI_DEFAULT_MODEL:-qwen2.5-coder:7b}}"
                _archmind_menu_pause
                ;;
            6)
                local model
                read "model?Model to remove: "
                archmind_ai_remove "$model"
                _archmind_menu_pause
                ;;
            7)
                local model
                read "model?New default model: "

                if [[ -n "$model" ]]; then
                    archmind_config_set ARCHMIND_AI_DEFAULT_MODEL "$model"
                else
                    _archmind_warn "The model cannot be empty."
                fi

                _archmind_menu_pause
                ;;
            8)
                archmind_ai_gpu
                _archmind_menu_pause
                ;;
            9)
                archmind_ai_start
                _archmind_menu_pause
                ;;
            10)
                archmind_ai_stop_service
                _archmind_menu_pause
                ;;
            0)
                return 0
                ;;
            *)
                _archmind_warn "Invalid option."
                sleep 1
                ;;
        esac
    done
}

_archmind_menu_config() {
    while true; do
        _archmind_menu_header

        print -P "%F{cyan}%BSETTINGS%b%f"
        echo
        echo "  1) Show settings"
        echo "  2) Change default model"
        echo "  3) Enable/disable startup screen"
        echo "  4) Enable/disable Fastfetch"
        echo "  5) Enable/disable menu clearing"
        echo "  6) Enable/disable menu pause"
        echo "  7) Change virtualenv directory"
        echo "  8) Change editor"
        echo "  9) Edit file manually"
        echo " 10) Restore defaults"
        echo
        echo "  0) Back"
        echo

        local choice
        read "choice?Choice: "

        case "$choice" in
            1)
                archmind_config_show
                _archmind_menu_pause
                ;;
            2)
                local model
                read "model?Default model: "

                if [[ -n "$model" ]]; then
                    archmind_config_set ARCHMIND_AI_DEFAULT_MODEL "$model"
                else
                    _archmind_warn "The model cannot be empty."
                fi

                _archmind_menu_pause
                ;;
            3)
                if [[ "${ARCHMIND_STARTUP_ENABLED:-true}" == "true" ]]; then
                    archmind_config_set ARCHMIND_STARTUP_ENABLED false
                else
                    archmind_config_set ARCHMIND_STARTUP_ENABLED true
                fi

                _archmind_menu_pause
                ;;
            4)
                if [[ "${ARCHMIND_STARTUP_FASTFETCH:-true}" == "true" ]]; then
                    archmind_config_set ARCHMIND_STARTUP_FASTFETCH false
                else
                    archmind_config_set ARCHMIND_STARTUP_FASTFETCH true
                fi

                _archmind_menu_pause
                ;;
            5)
                if [[ "${ARCHMIND_MENU_CLEAR:-true}" == "true" ]]; then
                    archmind_config_set ARCHMIND_MENU_CLEAR false
                else
                    archmind_config_set ARCHMIND_MENU_CLEAR true
                fi

                _archmind_menu_pause
                ;;
            6)
                if [[ "${ARCHMIND_MENU_PAUSE:-true}" == "true" ]]; then
                    archmind_config_set ARCHMIND_MENU_PAUSE false
                else
                    archmind_config_set ARCHMIND_MENU_PAUSE true
                fi

                _archmind_menu_pause
                ;;
            7)
                local directory
                read "directory?Virtualenv directory [.venv]: "
                archmind_config_set ARCHMIND_VENV_DIR "${directory:-.venv}"
                _archmind_menu_pause
                ;;
            8)
                local editor
                read "editor?Editor: "

                if [[ -n "$editor" ]]; then
                    archmind_config_set ARCHMIND_EDITOR "$editor"
                else
                    _archmind_warn "The editor cannot be empty."
                fi

                _archmind_menu_pause
                ;;
            9)
                archmind_config_edit
                ;;
            10)
                archmind_config_reset
                _archmind_menu_pause
                ;;
            0)
                return 0
                ;;
            *)
                _archmind_warn "Invalid option."
                sleep 1
                ;;
        esac
    done
}

archmind_menu() {
    while true; do
        _archmind_menu_header

        echo "  1) System"
        echo "  2) Monitoring"
        echo "  3) Local intelligence"
        echo "  4) Git"
        echo "  5) Python"
        echo "  6) Settings"
        echo "  7) Backup, restoration, and installation"
        echo "  8) ArchMind Doctor"
        echo "  9) About"
        echo " 10) Help"
        echo
        echo "  0) Exit"
        echo

        local choice
        read "choice?Choose an option: "

        case "$choice" in
            1)
                _archmind_menu_system
                ;;
            2)
                _archmind_menu_monitor
                ;;
            3)
                _archmind_menu_ai
                ;;
            4)
                _archmind_menu_git
                ;;
            5)
                _archmind_menu_python
                ;;
            6)
                _archmind_menu_config
                ;;
            7)
                archmind_manager
                ;;
            8)
                archmind_doctor
                _archmind_menu_pause
                ;;
            9)
                archmind_about
                _archmind_menu_pause
                ;;
            10)
                archmind_help
                _archmind_menu_pause
                ;;
            0|q|Q)
                if [[ "${ARCHMIND_MENU_CLEAR:-true}" == "true" ]]; then
                    clear
                fi
                return 0
                ;;
            *)
                _archmind_warn "Invalid option."
                sleep 1
                ;;
        esac
    done
}
