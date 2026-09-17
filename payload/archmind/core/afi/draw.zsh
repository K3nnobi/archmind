#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/palette.zsh"
source "$AFI_ROOT/layout.zsh"

afi_repeat() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local character="${1:- }"
    local count="${2:-0}"
    local output=""
    local index=0

    [[ "$count" == <-> ]] || count=0
    (( count <= 0 )) && return 0

    for (( index = 0; index < count; index++ )); do
        output+="$character"
    done

    print -nr -- "$output"
}

afi_spaces() {
    emulate -L zsh
    afi_repeat " " "${1:-0}"
}

afi_strip_ansi() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local text="${1:-}"

    # Remove ANSI SGR color/style sequences.
    print -nr -- "$text" |
        sed $'s/\033\\[[0-9;]*m//g'
}

afi_visible_length() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local text="${1:-}"
    local plain=""

    plain="$(afi_strip_ansi "$text")"

    print -r -- "${#plain}"
}

afi_truncate_text() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local text="${1:-}"
    local width="${2:-1}"

    (( width < 1 )) && return 0

    if (( ${#text} <= width )); then
        print -nr -- "$text"
        return 0
    fi

    if (( width == 1 )); then
        print -nr -- "…"
    else
        print -nr -- "${text[1,$(( width - 1 ))]}…"
    fi
}

afi_fit_text() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local text="${1:-}"
    local width="${2:-1}"
    local visible_length

    (( width < 1 )) && width=1

    visible_length="$(afi_visible_length "$text")"

    if (( visible_length > width )); then
        # Normal panel content should not contain ANSI while truncating.
        text="$(afi_strip_ansi "$text")"
        afi_truncate_text "$text" "$width"
        return 0
    fi

    print -nr -- "$text"
    afi_spaces $(( width - visible_length ))
}

afi_border_top() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local width="${1:-full}"
    width="$(afi_resolve_width "$width")"

    (( width < 2 )) && return 0

    printf '%s┌' "$AFI_PRIMARY"
    afi_repeat "─" $(( width - 2 ))
    printf '┐%s\n' "$AFI_RESET"
}

afi_border_bottom() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local width="${1:-full}"
    width="$(afi_resolve_width "$width")"

    (( width < 2 )) && return 0

    printf '%s└' "$AFI_PRIMARY"
    afi_repeat "─" $(( width - 2 ))
    printf '┘%s\n' "$AFI_RESET"
}

afi_empty_row() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local width="${1:-full}"
    width="$(afi_resolve_width "$width")"

    (( width < 2 )) && return 0

    printf '%s│%s' "$AFI_PRIMARY" "$AFI_RESET"
    afi_spaces $(( width - 2 ))
    printf '%s│%s\n' "$AFI_PRIMARY" "$AFI_RESET"
}

afi_row_lr() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local left_text="${1:-}"
    local right_text="${2:-}"
    local width="${3:-full}"
    local left_color="${4:-$AFI_TEXT}"
    local right_color="${5:-$AFI_TEXT}"

    local inner
    local left_length
    local right_length
    local spacing
    local available_left

    width="$(afi_resolve_width "$width")"
    inner=$(( width - 2 ))

    (( inner < 1 )) && return 0

    left_length="$(afi_visible_length "$left_text")"
    right_length="$(afi_visible_length "$right_text")"

    # When the row becomes narrow, preserve the left identity and drop the
    # secondary right label instead of allowing it to cross the border.
    if (( right_length + 1 >= inner )); then
        right_text=""
        right_length=0
    fi

    available_left=$(( inner - right_length ))
    (( right_length > 0 )) && (( available_left-- ))
    (( available_left < 1 )) && available_left=1

    if (( left_length > available_left )); then
        left_text="$(afi_truncate_text "$left_text" "$available_left")"
        left_length="$(afi_visible_length "$left_text")"
    fi

    spacing=$(( inner - left_length - right_length ))
    (( right_length > 0 && spacing < 1 )) && spacing=1
    (( right_length == 0 && spacing < 0 )) && spacing=0

    printf '%s│%s' "$AFI_PRIMARY" "$AFI_RESET"
    printf '%s%s%s' "$left_color" "$left_text" "$AFI_RESET"
    afi_spaces "$spacing"
    printf '%s%s%s' "$right_color" "$right_text" "$AFI_RESET"
    printf '%s│%s\n' "$AFI_PRIMARY" "$AFI_RESET"
}
