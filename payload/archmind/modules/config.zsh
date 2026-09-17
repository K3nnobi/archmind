# ==========================================
# ArchMind Configuration Module
# Intelligence meets Linux
# ==========================================

_archmind_config_file() {
    print -r -- "${ARCHMIND_USER_CONFIG:-$HOME/ArchMind/Config}/settings.zsh"
}

_archmind_config_require_file() {
    local config_file
    config_file="$(_archmind_config_file)"

    if [[ ! -f "$config_file" ]]; then
        _archmind_error "Configuration file not found."
        printf "Expected at: %s\n" "$config_file"
        return 1
    fi
}

_archmind_config_valid_key() {
    case "$1" in
        ARCHMIND_THEME|\
        ARCHMIND_AI_DEFAULT_MODEL|\
        ARCHMIND_STARTUP_ENABLED|\
        ARCHMIND_STARTUP_CLEAR|\
        ARCHMIND_STARTUP_FASTFETCH|\
        ARCHMIND_CONFIRM_ACTIONS|\
        ARCHMIND_UPDATE_CHECK|\
        ARCHMIND_VENV_DIR|\
        ARCHMIND_EDITOR|\
        ARCHMIND_MENU_CLEAR|\
        ARCHMIND_MENU_PAUSE)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_archmind_config_valid_boolean() {
    case "${1:l}" in
        true|false)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_archmind_config_is_boolean_key() {
    case "$1" in
        ARCHMIND_STARTUP_ENABLED|\
        ARCHMIND_STARTUP_CLEAR|\
        ARCHMIND_STARTUP_FASTFETCH|\
        ARCHMIND_CONFIRM_ACTIONS|\
        ARCHMIND_UPDATE_CHECK|\
        ARCHMIND_MENU_CLEAR|\
        ARCHMIND_MENU_PAUSE)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_archmind_config_escape_value() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//\$/\\\$}"
    value="${value//\`/\\\`}"

    print -r -- "$value"
}

_archmind_config_write() {
    local key="$1"
    local value="$2"
    local config_file
    local escaped_value
    local temporary_file

    config_file="$(_archmind_config_file)"
    escaped_value="$(_archmind_config_escape_value "$value")"
    temporary_file="${config_file}.tmp.$$"

    if grep -q "^export ${key}=" "$config_file" 2>/dev/null; then
        awk \
            -v key="$key" \
            -v value="$escaped_value" \
            '
            $0 ~ "^export " key "=" {
                print "export " key "=\"" value "\""
                next
            }

            {
                print
            }
            ' "$config_file" > "$temporary_file"
    else
        cat "$config_file" > "$temporary_file"
        printf 'export %s="%s"\n' "$key" "$escaped_value" >> "$temporary_file"
    fi

    if mv "$temporary_file" "$config_file"; then
        export "$key=$value"
        return 0
    fi

    rm -f "$temporary_file"
    return 1
}

archmind_config_show() {
    _archmind_config_require_file || return 1

    echo
    print -P "%F{cyan}%BARCHMIND CONFIG%b%f"
    print -P "%F{magenta}Current settings%f"
    echo

    printf "%-27s %s\n" "Theme:" "$ARCHMIND_THEME"
    printf "%-27s %s\n" "AI model:" "$ARCHMIND_AI_DEFAULT_MODEL"
    printf "%-27s %s\n" "Startup:" "$ARCHMIND_STARTUP_ENABLED"
    printf "%-27s %s\n" "Clear on startup:" "$ARCHMIND_STARTUP_CLEAR"
    printf "%-27s %s\n" "Startup Fastfetch:" "$ARCHMIND_STARTUP_FASTFETCH"
    printf "%-27s %s\n" "Confirm actions:" "$ARCHMIND_CONFIRM_ACTIONS"
    printf "%-27s %s\n" "Check updates:" "$ARCHMIND_UPDATE_CHECK"
    printf "%-27s %s\n" "Virtualenv directory:" "$ARCHMIND_VENV_DIR"
    printf "%-27s %s\n" "Editor:" "$ARCHMIND_EDITOR"
    printf "%-27s %s\n" "Clear menus:" "$ARCHMIND_MENU_CLEAR"
    printf "%-27s %s\n" "Pause after commands:" "$ARCHMIND_MENU_PAUSE"

    echo
    printf "File: %s\n" "$(_archmind_config_file)"
    echo
}

archmind_config_get() {
    local key="$1"

    if [[ -z "$key" ]]; then
        _archmind_error "Specify the setting name."
        echo
        echo "Example:"
        echo "  archmind config get ARCHMIND_THEME"
        return 1
    fi

    if ! _archmind_config_valid_key "$key"; then
        _archmind_error "Unknown setting: $key"
        return 1
    fi

    print -r -- "${(P)key}"
}

archmind_config_set() {
    _archmind_config_require_file || return 1

    local key="$1"
    local value="$2"

    if [[ -z "$key" || -z "$value" ]]; then
        _archmind_error "Specify the setting and its new value."
        echo
        echo "Example:"
        echo "  archmind config set ARCHMIND_THEME cyber"
        return 1
    fi

    if ! _archmind_config_valid_key "$key"; then
        _archmind_error "Setting not allowed: $key"
        return 1
    fi

    if _archmind_config_is_boolean_key "$key"; then
        value="${value:l}"

        if ! _archmind_config_valid_boolean "$value"; then
            _archmind_error "This setting accepts only true or false."
            return 1
        fi
    fi

    if _archmind_config_write "$key" "$value"; then
        _archmind_ok "$key changed to '$value'"
    else
        _archmind_error "Could not save the setting."
        return 1
    fi
}

archmind_config_edit() {
    _archmind_config_require_file || return 1

    local editor="${ARCHMIND_EDITOR:-${EDITOR:-nano}}"
    local editor_command

    editor_command="${editor%% *}"

    if ! command -v "$editor_command" >/dev/null 2>&1; then
        _archmind_error "Editor not found: $editor_command"
        return 1
    fi

    "$editor" "$(_archmind_config_file)"
}

archmind_config_reload() {
    _archmind_config_require_file || return 1

    source "$(_archmind_config_file)"
    _archmind_ok "Settings reloaded."
}

archmind_config_reset() {
    local config_file
    config_file="$(_archmind_config_file)"

    echo
    print -P "%F{yellow}%BRESTORE SETTINGS%b%f"
    echo
    echo "Current settings will be replaced with defaults."
    echo

    local confirmation
    read "confirmation?Continue? [y/N] "

    case "${confirmation:l}" in
        y|yes)
            cat > "$config_file" <<'EOF'
# ==========================================
# ArchMind User Settings
# ==========================================

export ARCHMIND_THEME="cyber"
export ARCHMIND_AI_DEFAULT_MODEL="qwen2.5-coder:7b"

export ARCHMIND_STARTUP_ENABLED="true"
export ARCHMIND_STARTUP_CLEAR="false"
export ARCHMIND_STARTUP_FASTFETCH="true"

export ARCHMIND_CONFIRM_ACTIONS="true"
export ARCHMIND_UPDATE_CHECK="true"

export ARCHMIND_VENV_DIR=".venv"
export ARCHMIND_EDITOR="${EDITOR:-nano}"

export ARCHMIND_MENU_CLEAR="true"
export ARCHMIND_MENU_PAUSE="true"
EOF

            source "$config_file"
            _archmind_ok "Settings restored."
            ;;
        *)
            _archmind_warn "Restoration cancelled."
            return 1
            ;;
    esac
}

archmind_config_help() {
    echo
    print -P "%F{cyan}%BARCHMIND CONFIG%b%f"
    echo
    echo "Usage:"
    echo "  archmind config show"
    echo "  archmind config get CHAVE"
    echo "  archmind config set CHAVE VALOR"
    echo "  archmind config edit"
    echo "  archmind config reload"
    echo "  archmind config reset"
    echo
    echo "Exemplos:"
    echo "  archmind config set ARCHMIND_THEME cyber"
    echo "  archmind config set ARCHMIND_MENU_CLEAR false"
    echo "  archmind config set ARCHMIND_AI_DEFAULT_MODEL qwen2.5-coder:7b"
    echo
}

archmind_config() {
    local command="${1:-show}"

    if (( $# > 0 )); then
        shift
    fi

    case "$command" in
        show|list)
            archmind_config_show
            ;;
        get)
            archmind_config_get "$@"
            ;;
        set)
            archmind_config_set "$@"
            ;;
        edit)
            archmind_config_edit
            ;;
        reload)
            archmind_config_reload
            ;;
        reset)
            archmind_config_reset
            ;;
        help|--help|-h)
            archmind_config_help
            ;;
        *)
            _archmind_error "Unknown configuration command: $command"
            echo "Use: archmind config help"
            return 1
            ;;
    esac
}
