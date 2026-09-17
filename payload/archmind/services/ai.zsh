#!/usr/bin/env zsh

# Preferred model. It can be overridden in the environment:
# export ARCHMIND_AI_MODEL="qwen2.5-coder:7b"
typeset -g ARCHMIND_AI_MODEL="${ARCHMIND_AI_MODEL:-qwen2.5-coder:7b}"

ai_ollama_installed() {
    emulate -L zsh
    command -v ollama >/dev/null 2>&1
}

ai_ollama_service_state() {
    emulate -L zsh

    if ! ai_ollama_installed; then
        print -r -- "Not installed"
        return 1
    fi

    if systemctl --user is-active --quiet ollama.service 2>/dev/null; then
        print -r -- "Active"
        return 0
    fi

    if systemctl is-active --quiet ollama.service 2>/dev/null; then
        print -r -- "Active"
        return 0
    fi

    if pgrep -x ollama >/dev/null 2>&1; then
        print -r -- "Active"
        return 0
    fi

    print -r -- "Inactive"
    return 1
}

ai_ollama_api_state() {
    emulate -L zsh

    if command -v curl >/dev/null 2>&1 &&
       curl -fsS --max-time 1 \
           http://127.0.0.1:11434/api/tags \
           >/dev/null 2>&1; then
        print -r -- "Online"
        return 0
    fi

    print -r -- "Offline"
    return 1
}

ai_list_model_names() {
    emulate -L zsh
    setopt localoptions typesetsilent

    ai_ollama_installed || return 1

    ollama list 2>/dev/null |
        awk 'NR > 1 && NF > 0 {print $1}'
}

ai_model_count() {
    emulate -L zsh

    local count=0

    count="$(
        ai_list_model_names 2>/dev/null |
            sed '/^[[:space:]]*$/d' |
            wc -l |
            tr -d ' '
    )"

    [[ "$count" == <-> ]] || count=0
    print -r -- "$count"
}

ai_model_exists() {
    emulate -L zsh

    local requested="${1:-}"

    [[ -n "$requested" ]] || return 1

    ai_list_model_names 2>/dev/null |
        grep -Fxq -- "$requested"
}

ai_first_model() {
    emulate -L zsh

    ai_list_model_names 2>/dev/null |
        head -n 1
}

ai_resolve_default_model() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local first=""

    if ai_model_exists "$ARCHMIND_AI_MODEL"; then
        print -r -- "$ARCHMIND_AI_MODEL"
        return 0
    fi

    first="$(ai_first_model)"

    if [[ -n "$first" ]]; then
        print -r -- "$first"
        return 0
    fi

    print -r -- "$ARCHMIND_AI_MODEL"
    return 1
}

ai_collect_status() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga AI_STATUS_LINES

    local binary="Missing"
    local service="Unavailable"
    local api="Offline"
    local model_count=0
    local default_model="None"
    local version="Unavailable"

    if ai_ollama_installed; then
        binary="$(command -v ollama)"
        version="$(ollama --version 2>/dev/null | head -n 1)"
        service="$(ai_ollama_service_state)" || true
        api="$(ai_ollama_api_state)" || true
        model_count="$(ai_model_count)"
        default_model="$(ai_resolve_default_model)" || true
    fi

    AI_STATUS_LINES=(
        "Executable .......... ${binary}"
        "Version .............. ${version}"
        "Service ............. ${service}"
        "Local API ........... ${api}"
        "Installed models .. ${model_count}"
        "Default model ....... ${default_model}"
        "Endpoint ............ http://127.0.0.1:11434"
    )
}

ai_collect_models() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga AI_MODEL_LINES

    local output=""

    if ! ai_ollama_installed; then
        AI_MODEL_LINES=(
            "Ollama is not installed."
        )
        return 1
    fi

    output="$(ollama list 2>/dev/null)"

    if [[ -z "$output" ]]; then
        AI_MODEL_LINES=(
            "No models were found."
        )
        return 0
    fi

    AI_MODEL_LINES=(
        "Available models:"
        ""
        "$output"
    )
}

ai_collect_running_models() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga AI_RUNNING_LINES

    local output=""

    if ! ai_ollama_installed; then
        AI_RUNNING_LINES=("Ollama is not installed.")
        return 1
    fi

    output="$(ollama ps 2>/dev/null)"

    if [[ -z "$output" ]] ||
       (( $(print -r -- "$output" | wc -l) <= 1 )); then
        AI_RUNNING_LINES=(
            "No models are loaded into memory."
        )
        return 0
    fi

    AI_RUNNING_LINES=(
        "Currently loaded models:"
        ""
        "$output"
    )
}

ai_run_chat() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local model=""
    local service_state=""

    if ! ai_ollama_installed; then
        print -u2 -- "Ollama is not installed."
        return 1
    fi

    model="$(ai_resolve_default_model)" || {
        print -u2 -- "No installed model was found."
        print -u2 -- "Expected model: $ARCHMIND_AI_MODEL"
        return 1
    }

    service_state="$(ai_ollama_api_state)" || true

    if [[ "$service_state" != "Online" ]]; then
        print -u2 -- "The local Ollama API is offline."
        print -u2 -- "Start Ollama before opening the assistant."
        return 1
    fi

    print -r -- "Opening model: $model"
    print

    ollama run "$model"
}
