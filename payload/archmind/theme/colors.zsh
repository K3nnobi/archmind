# ==========================================
# ArchMind Cyber Colors
# Intelligence meets Linux
# ==========================================

typeset -g ARCHMIND_COLOR_PRIMARY="39"
typeset -g ARCHMIND_COLOR_SECONDARY="45"
typeset -g ARCHMIND_COLOR_ACCENT="99"

typeset -g ARCHMIND_COLOR_SUCCESS="82"
typeset -g ARCHMIND_COLOR_WARNING="220"
typeset -g ARCHMIND_COLOR_ERROR="196"
typeset -g ARCHMIND_COLOR_MUTED="245"
typeset -g ARCHMIND_COLOR_TEXT="255"

_archmind_color() {
    local color="$1"
    shift

    print -P "%F{$color}$*%f"
}

_archmind_bold() {
    print -P "%B$*%b"
}

_archmind_title() {
    print -P "%F{$ARCHMIND_COLOR_PRIMARY}%B$*%b%f"
}

_archmind_subtitle() {
    print -P "%F{$ARCHMIND_COLOR_ACCENT}$*%f"
}

_archmind_muted() {
    print -P "%F{$ARCHMIND_COLOR_MUTED}$*%f"
}

_archmind_success() {
    print -P "%F{$ARCHMIND_COLOR_SUCCESS}✔%f $*"
}

_archmind_warning() {
    print -P "%F{$ARCHMIND_COLOR_WARNING}⚠%f $*"
}

_archmind_failure() {
    print -P "%F{$ARCHMIND_COLOR_ERROR}✖%f $*"
}

_archmind_separator() {
    local width="${1:-46}"
    local line=""

    while (( ${#line} < width )); do
        line+="─"
    done

    print -P "%F{$ARCHMIND_COLOR_MUTED}${line}%f"
}
