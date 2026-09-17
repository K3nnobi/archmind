#!/usr/bin/env zsh

typeset -g ARCHMIND_DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}"
typeset -g ARCHMIND_USER_CONFIG="${ARCHMIND_USER_CONFIG:-$ARCHMIND_DATA_HOME/Config}"
typeset -g ARCHMIND_SETTINGS_FILE="$ARCHMIND_USER_CONFIG/settings.zsh"

settings_load() {
    emulate -L zsh

    if [[ -r "$ARCHMIND_SETTINGS_FILE" ]]; then
        source "$ARCHMIND_SETTINGS_FILE"
    fi

    typeset -g ARCHMIND_AI_MODEL="${ARCHMIND_AI_MODEL:-qwen2.5-coder:7b}"
    typeset -g ARCHMIND_BACKUP_DIR="${ARCHMIND_BACKUP_DIR:-$HOME/ArchMind/Backups}"
    typeset -g ARCHMIND_PYTHON_PROJECT="${ARCHMIND_PYTHON_PROJECT:-$HOME/ArchMind/Projects}"
    typeset -g ARCHMIND_CONSOLE_MARGIN="${ARCHMIND_CONSOLE_MARGIN:-2}"
    typeset -g ARCHMIND_CONSOLE_MIN_WIDTH="${ARCHMIND_CONSOLE_MIN_WIDTH:-40}"
    typeset -g ARCHMIND_SAFE_CONFIRMATIONS="${ARCHMIND_SAFE_CONFIRMATIONS:-true}"
}

settings_escape_zsh() {
    emulate -L zsh

    local value="${1:-}"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//\$/\\\$}"
    value="${value//\`/\\\`}"

    print -r -- "$value"
}

settings_save() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local directory="${ARCHMIND_SETTINGS_FILE:h}"
    local temp_file="${ARCHMIND_SETTINGS_FILE}.tmp"
    local ai_model
    local backup_dir
    local python_project

    mkdir -p "$directory" || return 1

    ai_model="$(settings_escape_zsh "$ARCHMIND_AI_MODEL")"
    backup_dir="$(settings_escape_zsh "$ARCHMIND_BACKUP_DIR")"
    python_project="$(settings_escape_zsh "$ARCHMIND_PYTHON_PROJECT")"

    cat > "$temp_file" <<EOF_SETTINGS
#!/usr/bin/env zsh

typeset -g ARCHMIND_AI_MODEL="$ai_model"
typeset -g ARCHMIND_BACKUP_DIR="$backup_dir"
typeset -g ARCHMIND_PYTHON_PROJECT="$python_project"
typeset -g ARCHMIND_CONSOLE_MARGIN=$ARCHMIND_CONSOLE_MARGIN
typeset -g ARCHMIND_CONSOLE_MIN_WIDTH=$ARCHMIND_CONSOLE_MIN_WIDTH
typeset -g ARCHMIND_SAFE_CONFIRMATIONS=$ARCHMIND_SAFE_CONFIRMATIONS
EOF_SETTINGS

    mv -f "$temp_file" "$ARCHMIND_SETTINGS_FILE"
}

settings_collect_information() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga SETTINGS_INFORMATION_LINES

    settings_load

    SETTINGS_INFORMATION_LINES=(
        "File ............. ${ARCHMIND_SETTINGS_FILE}"
        ""
        "AI model ........ ${ARCHMIND_AI_MODEL}"
        "Backup directory . ${ARCHMIND_BACKUP_DIR}"
        "Python project ...... ${ARCHMIND_PYTHON_PROJECT}"
        "Console margin ... ${ARCHMIND_CONSOLE_MARGIN}"
        "Minimum width ...... ${ARCHMIND_CONSOLE_MIN_WIDTH}"
        "Confirmations ........ ${ARCHMIND_SAFE_CONFIRMATIONS}"
    )
}

settings_read_value() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local prompt="${1:-New value}"
    local current="${2:-}"
    local input=""

    print -r -- "$prompt"
    print -r -- "Current: $current"
    print
    print -nr -- "New value: "

    read -r input

    [[ -n "$input" ]] || return 1

    REPLY="$input"
}

settings_set_ai_model() {
    emulate -L zsh

    settings_load

    settings_read_value \
        "Default Ollama Model" \
        "$ARCHMIND_AI_MODEL" || return 1

    ARCHMIND_AI_MODEL="$REPLY"
    settings_save
}

settings_set_backup_dir() {
    emulate -L zsh

    settings_load

    settings_read_value \
        "Backup Directory" \
        "$ARCHMIND_BACKUP_DIR" || return 1

    local directory="${REPLY:A}"

    mkdir -p "$directory" || {
        print -u2 -- "Could not create directory:"
        print -u2 -- "$directory"
        return 1
    }

    ARCHMIND_BACKUP_DIR="$directory"
    settings_save
}

settings_set_python_project() {
    emulate -L zsh

    settings_load

    settings_read_value \
        "Python Project Directory" \
        "$ARCHMIND_PYTHON_PROJECT" || return 1

    local directory="${REPLY:A}"

    [[ -d "$directory" ]] || {
        print -u2 -- "Directory does not exist:"
        print -u2 -- "$directory"
        return 1
    }

    ARCHMIND_PYTHON_PROJECT="$directory"
    settings_save
}

settings_set_margin() {
    emulate -L zsh

    settings_load

    settings_read_value \
        "Console Margin" \
        "$ARCHMIND_CONSOLE_MARGIN" || return 1

    [[ "$REPLY" == <-> ]] || {
        print -u2 -- "Enter an integer."
        return 1
    }

    (( REPLY >= 0 && REPLY <= 10 )) || {
        print -u2 -- "Use a value between 0 and 10."
        return 1
    }

    ARCHMIND_CONSOLE_MARGIN="$REPLY"
    settings_save
}

settings_toggle_confirmations() {
    emulate -L zsh

    settings_load

    if [[ "$ARCHMIND_SAFE_CONFIRMATIONS" == "true" ]]; then
        ARCHMIND_SAFE_CONFIRMATIONS=false
    else
        ARCHMIND_SAFE_CONFIRMATIONS=true
    fi

    settings_save

    print -r -- "Safety confirmations: $ARCHMIND_SAFE_CONFIRMATIONS"
}

settings_restore_defaults() {
    emulate -L zsh

    typeset -g ARCHMIND_AI_MODEL="qwen2.5-coder:7b"
    typeset -g ARCHMIND_BACKUP_DIR="$HOME/ArchMind/Backups"
    typeset -g ARCHMIND_PYTHON_PROJECT="$HOME/ArchMind/Projects"
    typeset -g ARCHMIND_CONSOLE_MARGIN=2
    typeset -g ARCHMIND_CONSOLE_MIN_WIDTH=40
    typeset -g ARCHMIND_SAFE_CONFIRMATIONS=true

    mkdir -p "$ARCHMIND_BACKUP_DIR"

    settings_save
}
