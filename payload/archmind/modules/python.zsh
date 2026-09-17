# ==========================================
# ArchMind Python Module
# Intelligence meets Linux
# ==========================================

_archmind_python_command() {
    if command -v python >/dev/null 2>&1; then
        print -r -- "python"
    elif command -v python3 >/dev/null 2>&1; then
        print -r -- "python3"
    else
        return 1
    fi
}

_archmind_python_require() {
    if ! _archmind_python_command >/dev/null 2>&1; then
        _archmind_error "Python is not installed."
        echo "Install with:"
        echo "  sudo pacman -S python"
        return 1
    fi
}

_archmind_python_venv_path() {
    print -r -- "${ARCHMIND_VENV_DIR:-.venv}"
}

archmind_python_status() {
    _archmind_python_require || return 1

    local python_cmd
    local venv_path
    local project_python
    local project_pip

    python_cmd="$(_archmind_python_command)"
    venv_path="$(_archmind_python_venv_path)"
    project_python="$venv_path/bin/python"
    project_pip="$venv_path/bin/pip"

    echo
    print -P "%F{cyan}%BARCHMIND PYTHON%b%f"
    print -P "%F{magenta}Python environment status%f"
    echo

    printf "%-17s %s\n" "Python global:" "$($python_cmd --version 2>&1)"
    printf "%-17s %s\n" "Executable:" "$(command -v "$python_cmd")"
    printf "%-17s %s\n" "Project:" "$PWD"
    printf "%-17s %s\n" "Default environment:" "$venv_path"

    if [[ -n "$VIRTUAL_ENV" ]]; then
        _archmind_ok "Virtual environment active"
        printf "%-17s %s\n" "Virtualenv:" "$VIRTUAL_ENV"
        printf "%-17s %s\n" "Active Python:" "$(command -v python)"
        printf "%-17s %s\n" "Version:" "$(python --version 2>&1)"
    elif [[ -x "$project_python" ]]; then
        _archmind_warn "A virtual environment exists, but it is not active"
        printf "%-17s %s\n" "Local:" "$PWD/$venv_path"
        printf "%-17s %s\n" "Version:" "$("$project_python" --version 2>&1)"
    else
        _archmind_warn "No virtual environment found in this directory"
    fi

    if [[ -x "$project_pip" ]]; then
        local package_count

        package_count="$(
            "$project_pip" list \
                --format=freeze \
                --disable-pip-version-check \
                2>/dev/null |
            sed '/^[[:space:]]*$/d' |
            wc -l
        )"

        printf "%-17s %s\n" "Packages in venv:" "$package_count"
    fi

    echo
}

archmind_python_create() {
    _archmind_python_require || return 1

    local python_cmd
    local venv_path

    python_cmd="$(_archmind_python_command)"
    venv_path="${1:-$(_archmind_python_venv_path)}"

    if [[ -e "$venv_path" ]]; then
        _archmind_error "Path '$venv_path' already exists."
        return 1
    fi

    echo
    print -P "%F{cyan}%BCREATING PYTHON ENVIRONMENT%b%f"
    echo
    printf "Directory: %s\n" "$PWD/$venv_path"
    printf "Python:    %s\n" "$($python_cmd --version 2>&1)"
    echo

    "$python_cmd" -m venv "$venv_path" || {
        _archmind_error "Could not create the virtual environment."
        return 1
    }

    _archmind_ok "Virtual environment created at '$venv_path'"
    echo
    echo "Activate with:"
    echo "  archmind python activate"
    echo
}

archmind_python_activate() {
    local venv_path
    venv_path="${1:-$(_archmind_python_venv_path)}"

    if [[ ! -f "$venv_path/bin/activate" ]]; then
        _archmind_error "Virtual environment not found at '$venv_path'."
        echo
        echo "Create it with:"
        echo "  archmind python create"
        return 1
    fi

    source "$venv_path/bin/activate"

    _archmind_ok "Virtual environment activated"
    printf "Python: %s\n" "$(command -v python)"
    printf "Version: %s\n" "$(python --version 2>&1)"
}

archmind_python_deactivate() {
    if [[ -z "$VIRTUAL_ENV" ]]; then
        _archmind_warn "No virtual environment is active."
        return 1
    fi

    if (( $+functions[deactivate] )); then
        deactivate
    _archmind_ok "Virtual environment deactivated"
    else
        _archmind_error "The deactivate function is unavailable."
        return 1
    fi
}

archmind_python_install() {
    if [[ -z "$VIRTUAL_ENV" ]]; then
        _archmind_error "Activate a virtual environment before installing packages."
        echo
        echo "Use:"
        echo "  archmind python activate"
        return 1
    fi

    if (( $# == 0 )); then
        _archmind_error "Specify at least one package."
        echo
        echo "Example:"
        echo "  archmind python install requests pyte"
        return 1
    fi

    python -m pip install "$@"
}

archmind_python_requirements() {
    if [[ -z "$VIRTUAL_ENV" ]]; then
        _archmind_error "Activate a virtual environment first."
        return 1
    fi

    local requirements_file="${1:-requirements.txt}"

    if [[ ! -f "$requirements_file" ]]; then
        _archmind_error "File '$requirements_file' not found."
        return 1
    fi

    python -m pip install -r "$requirements_file"
}

archmind_python_freeze() {
    if [[ -z "$VIRTUAL_ENV" ]]; then
        _archmind_error "Activate a virtual environment first."
        return 1
    fi

    local output_file="${1:-requirements.txt}"

    python -m pip freeze > "$output_file" || {
        _archmind_error "Could not generate '$output_file'."
        return 1
    }

    _archmind_ok "Dependencies saved to '$output_file'"
}

archmind_python_list() {
    if [[ -n "$VIRTUAL_ENV" ]]; then
        python -m pip list
        return
    fi

    local venv_path
    venv_path="$(_archmind_python_venv_path)"

    if [[ -x "$venv_path/bin/python" ]]; then
        "$venv_path/bin/python" -m pip list
    else
        _archmind_error "No active or available virtual environment."
        return 1
    fi
}

archmind_python_outdated() {
    if [[ -n "$VIRTUAL_ENV" ]]; then
        python -m pip list --outdated
        return
    fi

    local venv_path
    venv_path="$(_archmind_python_venv_path)"

    if [[ -x "$venv_path/bin/python" ]]; then
        "$venv_path/bin/python" -m pip list --outdated
    else
        _archmind_error "No active or available virtual environment."
        return 1
    fi
}

archmind_python_run() {
    if (( $# == 0 )); then
        _archmind_error "Informe o script Python."
        echo
        echo "Example:"
        echo "  archmind python run main.py"
        return 1
    fi

    local script="$1"
    shift

    if [[ ! -f "$script" ]]; then
        _archmind_error "Script '$script' not found."
        return 1
    fi

    if [[ -n "$VIRTUAL_ENV" ]]; then
        python "$script" "$@"
        return
    fi

    local venv_path
    venv_path="$(_archmind_python_venv_path)"

    if [[ -x "$venv_path/bin/python" ]]; then
        "$venv_path/bin/python" "$script" "$@"
    else
        _archmind_warn "Executando com o Python global."
        local python_cmd
        python_cmd="$(_archmind_python_command)" || return 1
        "$python_cmd" "$script" "$@"
    fi
}

archmind_python_remove() {
    local venv_path
    venv_path="${1:-$(_archmind_python_venv_path)}"

    if [[ ! -d "$venv_path" ]]; then
        _archmind_error "Environment '$venv_path' not found."
        return 1
    fi

    if [[ "$VIRTUAL_ENV" == "$PWD/$venv_path" ]]; then
        _archmind_error "Deactivate the environment before removing it."
        echo "Use:"
        echo "  archmind python deactivate"
        return 1
    fi

    echo
    print -P "%F{yellow}%BREMOVE PYTHON ENVIRONMENT%b%f"
    echo
    printf "Directory: %s\n" "$PWD/$venv_path"
    echo

    local confirmation
    read "confirmation?Remove permanently? [y/N] "

    case "${confirmation:l}" in
        y|yes)
            rm -rf -- "$venv_path"
            _archmind_ok "Virtual environment removed"
            ;;
        *)
            _archmind_warn "Removal cancelled"
            return 1
            ;;
    esac
}

archmind_python_upgrade_pip() {
    if [[ -z "$VIRTUAL_ENV" ]]; then
        _archmind_error "Activate a virtual environment first."
        return 1
    fi

    python -m pip install --upgrade pip
}

archmind_python() {
    local command="${1:-status}"

    if (( $# > 0 )); then
        shift
    fi

    case "$command" in
        status)
            archmind_python_status
            ;;
        create|new)
            archmind_python_create "$@"
            ;;
        activate|on)
            archmind_python_activate "$@"
            ;;
        deactivate|off)
            archmind_python_deactivate
            ;;
        install|add)
            archmind_python_install "$@"
            ;;
        requirements|req)
            archmind_python_requirements "$@"
            ;;
        freeze)
            archmind_python_freeze "$@"
            ;;
        list)
            archmind_python_list
            ;;
        outdated)
            archmind_python_outdated
            ;;
        run)
            archmind_python_run "$@"
            ;;
        remove|delete)
            archmind_python_remove "$@"
            ;;
        upgrade-pip)
            archmind_python_upgrade_pip
            ;;
        help|--help|-h)
            echo
            print -P "%F{cyan}ArchMind Python%f"
            echo
            echo "Usage:"
            echo "  archmind python status"
            echo "  archmind python create [directory]"
            echo "  archmind python activate [directory]"
            echo "  archmind python deactivate"
            echo "  archmind python install package..."
            echo "  archmind python requirements [file]"
            echo "  archmind python freeze [file]"
            echo "  archmind python list"
            echo "  archmind python outdated"
            echo "  archmind python run script.py [argumentos]"
            echo "  archmind python upgrade-pip"
            echo "  archmind python remove [directory]"
            echo
            ;;
        *)
            _archmind_error "Unknown Python command: $command"
            echo "Use: archmind python help"
            return 1
            ;;
    esac
}

# Direct shortcuts

pyenv-create() {
    archmind_python_create "$@"
}

pyenv-on() {
    archmind_python_activate "$@"
}

pyenv-off() {
    archmind_python_deactivate
}

pyrun() {
    archmind_python_run "$@"
}

pystatus() {
    archmind_python_status
}
