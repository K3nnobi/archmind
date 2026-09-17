# ==========================================
# ArchMind Configuration Loader
# Intelligence meets Linux
# ==========================================

export ARCHMIND_CONFIG_DIR="${ARCHMIND_CONFIG_DIR:-$HOME/ArchMind/Config}"
export ARCHMIND_CONFIG_FILE="${ARCHMIND_CONFIG_FILE:-$ARCHMIND_CONFIG_DIR/archmind.conf}"

# Default values
export ARCHMIND_AI_DEFAULT_MODEL="${ARCHMIND_AI_DEFAULT_MODEL:-qwen2.5-coder:7b}"
export ARCHMIND_THEME="${ARCHMIND_THEME:-cyber}"
export ARCHMIND_STARTUP_ENABLED="${ARCHMIND_STARTUP_ENABLED:-true}"
export ARCHMIND_STARTUP_FASTFETCH="${ARCHMIND_STARTUP_FASTFETCH:-true}"
export ARCHMIND_CLEAR_MENU_ON_EXIT="${ARCHMIND_CLEAR_MENU_ON_EXIT:-true}"
export ARCHMIND_UPDATE_CHECK_AUR="${ARCHMIND_UPDATE_CHECK_AUR:-true}"
export ARCHMIND_VENV_DIR="${ARCHMIND_VENV_DIR:-.venv}"

_archmind_config_trim() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    print -r -- "$value"
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

_archmind_config_apply() {
    local key="$1"
    local value="$2"

    case "$key" in
        AI_DEFAULT_MODEL)
            [[ -n "$value" ]] &&
                export ARCHMIND_AI_DEFAULT_MODEL="$value"
            ;;

        THEME)
            [[ -n "$value" ]] &&
                export ARCHMIND_THEME="$value"
            ;;

        STARTUP_ENABLED)
            if _archmind_config_valid_boolean "$value"; then
                export ARCHMIND_STARTUP_ENABLED="${value:l}"
            fi
            ;;

        STARTUP_FASTFETCH)
            if _archmind_config_valid_boolean "$value"; then
                export ARCHMIND_STARTUP_FASTFETCH="${value:l}"
            fi
            ;;

        CLEAR_MENU_ON_EXIT)
            if _archmind_config_valid_boolean "$value"; then
                export ARCHMIND_CLEAR_MENU_ON_EXIT="${value:l}"
            fi
            ;;

        UPDATE_CHECK_AUR)
            if _archmind_config_valid_boolean "$value"; then
                export ARCHMIND_UPDATE_CHECK_AUR="${value:l}"
            fi
            ;;

        VENV_DIR)
            [[ -n "$value" ]] &&
                export ARCHMIND_VENV_DIR="$value"
            ;;
    esac
}

archmind_config_load() {
    [[ -f "$ARCHMIND_CONFIG_FILE" ]] || return 0

    local line
    local key
    local value

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(_archmind_config_trim "$line")"

        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue
        [[ "$line" != *"="* ]] && continue

        key="${line%%=*}"
        value="${line#*=}"

        key="$(_archmind_config_trim "$key")"
        value="$(_archmind_config_trim "$value")"

        _archmind_config_apply "$key" "$value"
    done < "$ARCHMIND_CONFIG_FILE"
}

archmind_config_load
