#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/draw.zsh"

afi_menu_render() {
    afi_menu_render_window "$1" "$2" "$3" 0 "${@:4}"
}

afi_menu_render_window() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local title="${1:-CONTROL CENTER}"
    local requested_width="${2:-55%}"
    local selected="${3:-1}"
    local max_visible="${4:-0}"

    shift 4

    local -a entries
    entries=("$@")

    local width
    local inner
    local content_width
    local title_label
    local remaining
    local total=${#entries[@]}
    local first_visible=1
    local last_visible="$total"
    local index=1
    local entry=""
    local label=""
    local fitted=""
    local prefix=""
    local top_hint=""
    local bottom_hint=""

    [[ "$selected" == <-> ]] || selected=1
    [[ "$max_visible" == <-> ]] || max_visible=0

    if (( max_visible > 0 && total > max_visible )); then
        first_visible=$(( selected - max_visible / 2 ))
        (( first_visible < 1 )) && first_visible=1
        (( first_visible > total - max_visible + 1 )) && \
            first_visible=$(( total - max_visible + 1 ))
        last_visible=$(( first_visible + max_visible - 1 ))
    else
        max_visible="$total"
    fi

    (( first_visible > 1 )) && top_hint="↑ More options"
    (( last_visible < total )) && bottom_hint="↓ More options"

    width="$(afi_resolve_width "$requested_width")"
    inner=$(( width - 2 ))
    content_width=$(( inner - 4 ))
    (( content_width < 1 )) && content_width=1

    title_label=" ${title:u} "
    if (( ${#title_label} > inner - 2 )); then
        title_label=" $(afi_truncate_text "${title:u}" $(( inner - 4 ))) "
    fi
    remaining=$(( inner - ${#title_label} - 1 ))
    (( remaining < 0 )) && remaining=0

    printf '%s┌─%s%s%s' \
        "$AFI_PRIMARY" \
        "$AFI_SECONDARY$AFI_BOLD" \
        "$title_label" \
        "$AFI_PRIMARY"

    afi_repeat "─" "$remaining"
    printf '┐%s\n' "$AFI_RESET"

    printf '%s│%s' "$AFI_PRIMARY" "$AFI_RESET"
    printf '%s%s%s' \
        "$AFI_MUTED" \
        "$(afi_fit_text "  $top_hint" "$inner")" \
        "$AFI_RESET"
    printf '%s│%s\n' "$AFI_PRIMARY" "$AFI_RESET"

    for (( index = first_visible; index <= last_visible; index++ )); do
        entry="${entries[$index]}"
        label="${entry%%::*}"

        if (( index == selected )); then
            prefix="▶ "
            fitted="$(afi_fit_text "${prefix}${label}" "$content_width")"

            printf '%s│%s  ' "$AFI_PRIMARY" "$AFI_RESET"
            printf '%s%s%s' \
                "${AFI_PRIMARY}${AFI_BOLD}" \
                "$fitted" \
                "$AFI_RESET"
            printf '  %s│%s\n' "$AFI_PRIMARY" "$AFI_RESET"
        else
            prefix="  "
            fitted="$(afi_fit_text "${prefix}${label}" "$content_width")"

            printf '%s│%s  ' "$AFI_PRIMARY" "$AFI_RESET"
            printf '%s%s%s' "$AFI_TEXT" "$fitted" "$AFI_RESET"
            printf '  %s│%s\n' "$AFI_PRIMARY" "$AFI_RESET"
        fi
    done

    printf '%s│%s' "$AFI_PRIMARY" "$AFI_RESET"
    printf '%s%s%s' \
        "$AFI_MUTED" \
        "$(afi_fit_text "  $bottom_hint" "$inner")" \
        "$AFI_RESET"
    printf '%s│%s\n' "$AFI_PRIMARY" "$AFI_RESET"

    printf '%s└' "$AFI_PRIMARY"
    afi_repeat "─" "$inner"
    printf '┘%s\n' "$AFI_RESET"
}

afi_menu_label() {
    emulate -L zsh

    local entry="${1:-}"
    print -r -- "${entry%%::*}"
}

afi_menu_description() {
    emulate -L zsh

    local entry="${1:-}"

    if [[ "$entry" == *"::"* ]]; then
        print -r -- "${entry#*::}"
    else
        print -r -- ""
    fi
}
