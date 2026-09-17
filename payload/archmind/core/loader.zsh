# ==========================================
# ArchMind Loader
# Intelligence meets Linux
# ==========================================

export ARCHMIND_HOME="${ARCHMIND_HOME:-$HOME/ArchMind/System/Core}"
export ARCHMIND_DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}"
export ARCHMIND_USER_CONFIG="${ARCHMIND_USER_CONFIG:-$ARCHMIND_DATA_HOME/Config}"

_archmind_source_file() {
    local file="$1"

    if [[ -r "$file" ]]; then
        source "$file"
        return 0
    fi

    return 1
}

# Required core

_archmind_source_file "$ARCHMIND_HOME/core/variables.zsh"
_archmind_source_file "$ARCHMIND_HOME/core/exports.zsh"

# User settings

if [[ -r "$ARCHMIND_USER_CONFIG/settings.zsh" ]]; then
    _archmind_source_file "$ARCHMIND_USER_CONFIG/settings.zsh"
else
    _archmind_source_file "$ARCHMIND_HOME/config/settings.zsh"
fi

# Remaining core

_archmind_source_file "$ARCHMIND_HOME/core/aliases.zsh"
_archmind_source_file "$ARCHMIND_HOME/core/functions.zsh"

# Modules

for module_file in "$ARCHMIND_HOME"/modules/*.zsh(N); do
    _archmind_source_file "$module_file"
done

# Theme

# Theme in controlled order
_archmind_source_file "$ARCHMIND_HOME/theme/palette.zsh"
_archmind_source_file "$ARCHMIND_HOME/theme/colors.zsh"
_archmind_source_file "$ARCHMIND_HOME/theme/icons.zsh"
_archmind_source_file "$ARCHMIND_HOME/theme/widgets.zsh"
_archmind_source_file "$ARCHMIND_HOME/theme/prompt.zsh"
_archmind_source_file "$ARCHMIND_HOME/theme/startup.zsh"
