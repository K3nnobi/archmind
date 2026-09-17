# ==========================================
# ArchMind Core Functions
# Intelligence meets Linux
# ==========================================

_archmind_ok() {
    print -P "%F{cyan}✔%f $1"
}

_archmind_warn() {
    print -P "%F{yellow}⚠%f $1"
}

_archmind_error() {
    print -P "%F{red}✘%f $1"
}

archmind_about() {
    echo
    print -P "%F{cyan}╔══════════════════════════════════════╗%f"
    printf "║ %-36s ║\n" "$ARCHMIND_NAME"
    printf "║ %-36s ║\n" "$ARCHMIND_MOTTO"
    print -P "%F{cyan}╠══════════════════════════════════════╣%f"
    printf "║ Version : %-25s ║\n" "$ARCHMIND_VERSION"
    printf "║ Codename: %-25s ║\n" "$ARCHMIND_CODENAME"
    printf "║ Theme   : %-25s ║\n" "$ARCHMIND_THEME"
    printf "║ AI      : %-25s ║\n" "$ARCHMIND_AI"
    printf "║ Shell   : %-25s ║\n" "$ARCHMIND_SHELL"
    printf "║ Author  : %-25s ║\n" "$ARCHMIND_AUTHOR"
    print -P "%F{cyan}╚══════════════════════════════════════╝%f"
    echo
}

archmind_doctor() {
    local errors=0
    local warnings=0

    echo
    print -P "%F{cyan}ARCHMIND DOCTOR%f"
    print -P "%F{magenta}Intelligence meets Linux%f"
    echo

    print -P "%BMain files%b"

    local required_files=(
        "$ARCHMIND_HOME/core/loader.zsh"
        "$ARCHMIND_HOME/core/variables.zsh"
        "$ARCHMIND_HOME/core/exports.zsh"
        "$ARCHMIND_HOME/core/aliases.zsh"
        "$ARCHMIND_HOME/core/functions.zsh"
        "$ARCHMIND_HOME/theme/colors.zsh"
        "$ARCHMIND_HOME/theme/icons.zsh"
        "$ARCHMIND_HOME/theme/prompt.zsh"
        "$ARCHMIND_HOME/theme/startup.zsh"
        "$ARCHMIND_HOME/modules/ai.zsh"
        "$ARCHMIND_HOME/modules/git.zsh"
        "$ARCHMIND_HOME/modules/monitor.zsh"
        "$ARCHMIND_HOME/modules/network.zsh"
        "$ARCHMIND_HOME/modules/python.zsh"
        "$ARCHMIND_HOME/modules/system.zsh"
        "$ARCHMIND_HOME/modules/menu.zsh"
	"$ARCHMIND_HOME/core/config.zsh"
	"$ARCHMIND_HOME/config/archmind.conf"
	"$ARCHMIND_HOME/modules/config.zsh"
	"$ARCHMIND_HOME/config/settings.zsh"
	"$ARCHMIND_HOME/modules/config.zsh"
    )

    local file
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            _archmind_ok "${file#$ARCHMIND_HOME/}"
        else
            _archmind_error "${file#$ARCHMIND_HOME/}"
            (( errors++ ))
        fi
    done

    echo
    print -P "%BDependencies%b"

    local commands=(
        zsh
        git
        python
        fastfetch
        btop
        ollama
    )

    local command_name
    for command_name in "${commands[@]}"; do
        if command -v "$command_name" >/dev/null 2>&1; then
            _archmind_ok "$command_name"
        else
            _archmind_warn "$command_name is not installed"
            (( warnings++ ))
        fi
    done

    echo
    print -P "%F{cyan}%BCONFIGURATION%b%f"
    echo

    if [[ -r "$ARCHMIND_CONFIG_FILE" ]]; then
        _archmind_ok "Configuration file is readable"
    else
        _archmind_error "Configuration file is inaccessible"
        ((errors++))
    fi

    if _archmind_config_valid_boolean "$ARCHMIND_STARTUP_ENABLED"; then
        _archmind_ok "STARTUP_ENABLED has a valid value"
    else
        _archmind_error "STARTUP_ENABLED has an invalid value"
        ((errors++))
    fi

    if _archmind_config_valid_boolean "$ARCHMIND_UPDATE_CHECK_AUR"; then
        _archmind_ok "UPDATE_CHECK_AUR has a valid value"
    else
        _archmind_error "UPDATE_CHECK_AUR has an invalid value"
        ((errors++))
    fi

    echo
    print -P "%BResult%b"

    if (( errors == 0 && warnings == 0 )); then
        print -P "%F{cyan}ArchMind system is healthy.%f"
    elif (( errors == 0 )); then
        print -P "%F{yellow}ArchMind is running with $warnings warning(s).%f"
    else
        print -P "%F{red}Found $errors error(s) and $warnings warning(s).%f"
    fi

    echo
}

archmind_help() {
    echo
    print -P "%F{cyan}ArchMind $ARCHMIND_VERSION%f"
    echo
    echo "Usage:"
    echo "  archmind              Show project information"
    echo "  archmind about        Show project information"
    echo "  archmind doctor       Check files and dependencies"
    echo "  archmind help         Show this help"
    echo "  archmind system       Show the machine summary"
    echo "  archmind memory       Show memory usage"
    echo "  archmind disk         Show disks and partitions"
    echo "  archmind battery      Show battery charge and health"
    echo "  archmind updates      Check available updates"
    echo "  archmind status       Show a quick machine overview"
    echo "  archmind monitor      Open btop, htop, or top"
    echo "  archmind temps        Show temperatures"
    echo "  archmind gpu          Show GPU information"
    echo "  archmind processes    List processes by CPU usage"
    echo "  archmind memps        List processes by memory usage"
    echo "  archmind git          Tools for Git repositories"
    echo "  archmind python       Manage Python projects and environments"
    echo "  archmind ai           Manage Ollama and local models"
    echo "  archmind manager      Backup, restoration, and installation"
    echo "  archmind              Open the interactive center"
    echo "  archmind menu         Open the interactive center"
    echo "  archmind config       Show and modify settings"
    echo "  archmind config       Manage ArchMind settings"
    echo "  archmind config       Manage ArchMind settings"
    echo
}

archmind() {
    case "${1:-menu}" in
        menu)
            archmind_menu
            ;;
        about)
            archmind_about
            ;;
        doctor)
            archmind_doctor
            ;;
        system|sys)
            archmind_system
            ;;
        memory|mem)
            archmind_memory
            ;;
        disk)
            archmind_disk
            ;;
        battery|bat)
            archmind_battery
            ;;
        updates)
            archmind_updates
            ;;
        manager|backup|restore|install)
            archmind_manager
            ;;
        status)
            archmind_status
            ;;
        monitor)
            archmind_monitor
            ;;
        temperatures|temps)
            archmind_temperatures
            ;;
        gpu)
            archmind_gpu
            ;;
        processes|ps)
            archmind_processes
            ;;
        memory-processes|memps)
            archmind_memory_processes
            ;;
        git)
            shift
            archmind_git "$@"
            ;;
        python|py)
            shift
            archmind_python "$@"
            ;;
        ai)
            shift
            archmind_ai "$@"
            ;;
        config|settings)
            shift
            archmind_config "$@"
            ;;
        config|settings)
            shift
            archmind_config "$@"
            ;;
        config|settings)
            shift
            archmind_config "$@"
            ;;
        help|--help|-h)
            archmind_help
            ;;
        *)
            _archmind_error "Unknown command: $1"
            archmind_help
            return 1
            ;;
    esac
}
