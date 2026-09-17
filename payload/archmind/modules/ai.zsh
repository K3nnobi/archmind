# ==========================================
# ArchMind AI Module
# Ollama and Local Models
# Intelligence meets Linux
# ==========================================

_archmind_ai_require_ollama() {
    if ! command -v ollama >/dev/null 2>&1; then
        _archmind_error "Ollama is not installed."
        echo
        echo "See:"
        echo "  archmind ai install-help"
        return 1
    fi
}

_archmind_ai_service_running() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet ollama 2>/dev/null && return 0
        systemctl --user is-active --quiet ollama 2>/dev/null && return 0
    fi

    pgrep -x ollama >/dev/null 2>&1
}

_archmind_ai_model_exists() {
    local model="$1"

    ollama list 2>/dev/null |
        awk 'NR > 1 {print $1}' |
        grep -Fxq -- "$model"
}

archmind_ai_status() {
    echo
    print -P "%F{cyan}%BARCHMIND AI%b%f"
    print -P "%F{magenta}Local intelligence status%f"
    echo

    if ! command -v ollama >/dev/null 2>&1; then
        printf "%-18s %s\n" "Ollama:" "not installed"
        printf "%-18s %s\n" "Default model:" "$ARCHMIND_AI_DEFAULT_MODEL"
        echo
        _archmind_warn "The module is loaded, but Ollama was not found."
        return 1
    fi

    printf "%-18s %s\n" "Executable:" "$(command -v ollama)"

    local version
    version="$(ollama --version 2>&1 | head -n 1)"
    printf "%-18s %s\n" "Version:" "$version"

    if _archmind_ai_service_running; then
        printf "%-18s %s\n" "Service:" "active"
    else
        printf "%-18s %s\n" "Service:" "inactive"
    fi

    printf "%-18s %s\n" "Default model:" "$ARCHMIND_AI_DEFAULT_MODEL"

    local model_count
    model_count="$(
        ollama list 2>/dev/null |
        awk 'NR > 1 && NF {count++} END {print count + 0}'
    )"

    printf "%-18s %s\n" "Local models:" "$model_count"

    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_name
        gpu_name="$(
            nvidia-smi \
                --query-gpu=name \
                --format=csv,noheader \
                2>/dev/null |
            head -n 1
        )"

        printf "%-18s %s\n" "NVIDIA GPU:" "${gpu_name:-not detected}"
    elif command -v lspci >/dev/null 2>&1; then
        local gpu_name
        gpu_name="$(
            lspci |
            grep -Ei 'vga|3d|display' |
            head -n 1 |
            sed 's/^[^ ]* //'
        )"

        printf "%-18s %s\n" "GPU:" "${gpu_name:-not detected}"
    fi

    echo
}

archmind_ai_start() {
    _archmind_ai_require_ollama || return 1

    if _archmind_ai_service_running; then
        _archmind_ok "The Ollama service is already active."
        return 0
    fi

    if systemctl list-unit-files ollama.service >/dev/null 2>&1; then
        sudo systemctl start ollama
    elif systemctl --user list-unit-files ollama.service >/dev/null 2>&1; then
        systemctl --user start ollama
    else
        _archmind_warn "systemd service not found."
        echo "Starting ollama serve in the background..."

        mkdir -p "$HOME/ArchMind/Logs" || return 1

        nohup ollama serve \
            >"$HOME/ArchMind/Logs/ollama.log" \
            2>&1 &

        sleep 2
    fi

    if _archmind_ai_service_running; then
        _archmind_ok "Ollama started."
    else
        _archmind_error "Could not start Ollama."
        return 1
    fi
}

archmind_ai_stop_service() {
    _archmind_ai_require_ollama || return 1

    if ! _archmind_ai_service_running; then
        _archmind_warn "The Ollama service is already inactive."
        return 0
    fi

    if systemctl is-active --quiet ollama 2>/dev/null; then
        sudo systemctl stop ollama
    elif systemctl --user is-active --quiet ollama 2>/dev/null; then
        systemctl --user stop ollama
    else
        pkill -x ollama
    fi

    if _archmind_ai_service_running; then
        _archmind_error "The service is still active."
        return 1
    fi

    _archmind_ok "Ollama service stopped."
}

archmind_ai_restart() {
    _archmind_ai_require_ollama || return 1

    if systemctl list-unit-files ollama.service >/dev/null 2>&1; then
        sudo systemctl restart ollama
    elif systemctl --user list-unit-files ollama.service >/dev/null 2>&1; then
        systemctl --user restart ollama
    else
        archmind_ai_stop_service
        archmind_ai_start
        return
    fi

    _archmind_ok "Ollama service restarted."
}

archmind_ai_logs() {
    _archmind_ai_require_ollama || return 1

    if systemctl list-unit-files ollama.service >/dev/null 2>&1; then
        journalctl -u ollama -n 100 --no-pager
    elif systemctl --user list-unit-files ollama.service >/dev/null 2>&1; then
        journalctl --user -u ollama -n 100 --no-pager
    elif [[ -f "$HOME/ArchMind/Logs/ollama.log" ]]; then
        tail -n 100 "$HOME/ArchMind/Logs/ollama.log"
    else
        _archmind_warn "No log file was found."
        return 1
    fi
}

archmind_ai_list() {
    _archmind_ai_require_ollama || return 1

    echo
    print -P "%F{cyan}%BINSTALLED MODELS%b%f"
    echo

    ollama list
    echo
}

archmind_ai_running() {
    _archmind_ai_require_ollama || return 1

    echo
    print -P "%F{cyan}%BRUNNING MODELS%b%f"
    echo

    ollama ps
    echo
}

archmind_ai_pull() {
    _archmind_ai_require_ollama || return 1

    local model="${1:-$ARCHMIND_AI_DEFAULT_MODEL}"

    echo
    print -P "%F{cyan}%BDOWNLOADING MODEL%b%f"
    echo
    printf "Model: %s\n\n" "$model"

    ollama pull "$model"
}

archmind_ai_remove() {
    _archmind_ai_require_ollama || return 1

    local model="$1"

    if [[ -z "$model" ]]; then
        _archmind_error "Specify the model to remove."
        echo
        echo "Example:"
        echo "  archmind ai remove qwen2.5-coder:3b"
        return 1
    fi

    if ! _archmind_ai_model_exists "$model"; then
        _archmind_error "Model '$model' is not installed."
        return 1
    fi

    echo
    print -P "%F{yellow}%BREMOVE MODEL%b%f"
    echo
    printf "Model: %s\n\n" "$model"

    local confirmation
    read "confirmation?Remove permanently? [y/N] "

    case "${confirmation:l}" in
        y|yes)
            ollama rm "$model"
            ;;
        *)
            _archmind_warn "Removal cancelled."
            return 1
            ;;
    esac
}

archmind_ai_run() {
    _archmind_ai_require_ollama || return 1

    local model="${1:-$ARCHMIND_AI_DEFAULT_MODEL}"

    if (( $# > 0 )); then
        shift
    fi

    if ! _archmind_ai_service_running; then
        _archmind_warn "The Ollama service is inactive."
        archmind_ai_start || return 1
    fi

    if ! _archmind_ai_model_exists "$model"; then
        _archmind_warn "Model '$model' is not installed yet."

        local confirmation
        read "confirmation?Download the model now? [y/N] "

        case "${confirmation:l}" in
            y|yes)
                ollama pull "$model" || return 1
                ;;
            *)
                _archmind_warn "Execution cancelled."
                return 1
                ;;
        esac
    fi

    if (( $# > 0 )); then
        ollama run "$model" "$*"
    else
        ollama run "$model"
    fi
}

archmind_ai_stop_model() {
    _archmind_ai_require_ollama || return 1

    local model="${1:-$ARCHMIND_AI_DEFAULT_MODEL}"

    ollama stop "$model"
}

archmind_ai_set_default() {
    local model="$1"

    if [[ -z "$model" ]]; then
        _archmind_error "Specify the default model."
        echo
        echo "Example:"
        echo "  archmind ai default qwen2.5-coder:7b"
        return 1
    fi

    local variables_file="$ARCHMIND_HOME/core/variables.zsh"

    if grep -q '^export ARCHMIND_AI_DEFAULT_MODEL=' "$variables_file" 2>/dev/null; then
        sed -i \
            "s|^export ARCHMIND_AI_DEFAULT_MODEL=.*|export ARCHMIND_AI_DEFAULT_MODEL=\"$model\"|" \
            "$variables_file"
    else
        echo \
            "export ARCHMIND_AI_DEFAULT_MODEL=\"$model\"" \
            >> "$variables_file"
    fi

    export ARCHMIND_AI_DEFAULT_MODEL="$model"

    _archmind_ok "Default model changed to '$model'."
}

archmind_ai_gpu() {
    _archmind_ai_require_ollama || return 1

    echo
    print -P "%F{cyan}%BAI AND GPU%b%f"
    echo

    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi
        echo
        print -P "%BOllama processes%b"
        ollama ps
    else
        _archmind_warn "nvidia-smi was not found."
        echo
        echo "Loaded models:"
        ollama ps
    fi

    echo
}

archmind_ai_install_help() {
    echo
    print -P "%F{cyan}%BOLLAMA INSTALLATION%b%f"
    echo
    echo "On Arch Linux, first search the repositories:"
    echo
    echo "  pacman -Ss ollama"
    echo
    echo "Then install the package suitable for your GPU."
    echo
    echo "After installation:"
    echo
    echo "  sudo systemctl enable --now ollama"
    echo
    echo "Validate with:"
    echo
    echo "  ollama --version"
    echo "  archmind ai status"
    echo
}

archmind_ai() {
    local command="${1:-status}"

    if (( $# > 0 )); then
        shift
    fi

    case "$command" in
        status)
            archmind_ai_status
            ;;
        start)
            archmind_ai_start
            ;;
        stop-service)
            archmind_ai_stop_service
            ;;
        restart)
            archmind_ai_restart
            ;;
        logs)
            archmind_ai_logs
            ;;
        list|models)
            archmind_ai_list
            ;;
        running|ps)
            archmind_ai_running
            ;;
        pull|download)
            archmind_ai_pull "$@"
            ;;
        remove|rm)
            archmind_ai_remove "$@"
            ;;
        run|chat)
            archmind_ai_run "$@"
            ;;
        stop)
            archmind_ai_stop_model "$@"
            ;;
        default)
            archmind_ai_set_default "$@"
            ;;
        gpu)
            archmind_ai_gpu
            ;;
        install-help)
            archmind_ai_install_help
            ;;
        help|--help|-h)
            echo
            print -P "%F{cyan}ArchMind AI%f"
            echo
            echo "Usage:"
            echo "  archmind ai status"
            echo "  archmind ai start"
            echo "  archmind ai stop-service"
            echo "  archmind ai restart"
            echo "  archmind ai logs"
            echo "  archmind ai list"
            echo "  archmind ai running"
            echo "  archmind ai pull [model]"
            echo "  archmind ai remove model"
            echo "  archmind ai run [model] [question]"
            echo "  archmind ai stop [model]"
            echo "  archmind ai default model"
            echo "  archmind ai gpu"
            echo
            ;;
        *)
            _archmind_error "Unknown AI command: $command"
            echo "Use: archmind ai help"
            return 1
            ;;
    esac
}

# Direct shortcuts

ai() {
    archmind_ai_run "$@"
}

qwen() {
    archmind_ai_run "$ARCHMIND_AI_DEFAULT_MODEL" "$@"
}

aimodels() {
    archmind_ai_list
}

aistatus() {
    archmind_ai_status
}

aigpu() {
    archmind_ai_gpu
}
