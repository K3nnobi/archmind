#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/layout.zsh"
source "$AFI_ROOT/draw.zsh"

afi_cursor_move() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local row="${1:-0}"
    local column="${2:-0}"
    local terminal_width
    local terminal_height

    terminal_width="$(afi_term_width)"
    terminal_height="$(afi_term_height)"

    [[ "$row" == <-> ]] || row=0
    [[ "$column" == <-> ]] || column=0

    (( row < 0 )) && row=0
    (( column < 0 )) && column=0
    (( row >= terminal_height )) && return 1
    (( column >= terminal_width )) && return 1

    printf '\e[%d;%dH' \
        $(( row + 1 )) \
        $(( column + 1 ))
}

afi_disable_wrap() {
    emulate -L zsh
    printf '\e[?7l'
}

afi_enable_wrap() {
    emulate -L zsh
    printf '\e[?7h'
}

afi_clear_screen() {
    emulate -L zsh

    printf '\e[2J\e[H'
}

afi_render_at() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local row="${1:-0}"
    local column="${2:-0}"
    local content="${3:-}"

    local terminal_width
    local terminal_height
    local available_width
    local current_row
    local current_line=""
    local visible_length=0
    local plain_line=""

    terminal_width="$(afi_term_width)"
    terminal_height="$(afi_term_height)"

    [[ "$row" == <-> ]] || row=0
    [[ "$column" == <-> ]] || column=0

    (( row < 0 )) && row=0
    (( column < 0 )) && column=0
    (( row >= terminal_height )) && return 0
    (( column >= terminal_width )) && return 0

    # Protect the physical last column from auto-wrap.
    available_width=$(( terminal_width - column - 1 ))

    (( available_width < 1 )) && return 0

    current_row="$row"

    while IFS= read -r current_line || [[ -n "$current_line" ]]; do
        (( current_row >= terminal_height )) && break

        visible_length="$(afi_visible_length "$current_line")"

        if (( visible_length > available_width )); then
            plain_line="$(afi_strip_ansi "$current_line")"
            current_line="${plain_line[1,$available_width]}"
        fi

        afi_cursor_move "$current_row" "$column" || break
        printf '%s' "$current_line"

        (( current_row++ ))
    done <<< "$content"
}

afi_clear_region() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local start_row="${1:-0}"
    local end_row="${2:-0}"
    local terminal_height
    local row

    terminal_height="$(afi_term_height)"

    [[ "$start_row" == <-> ]] || start_row=0
    [[ "$end_row" == <-> ]] || end_row="$start_row"

    (( start_row < 0 )) && start_row=0
    (( end_row >= terminal_height )) && \
        end_row=$(( terminal_height - 1 ))

    for (( row = start_row; row <= end_row; row++ )); do
        afi_cursor_move "$row" 0 || continue
        printf '\e[2K'
    done
}

afi_reset_terminal_state() {
    emulate -L zsh

    printf '%s' "${AFI_RESET:-$'\e[0m'}"
    afi_enable_wrap
    tput cnorm 2>/dev/null || true
}
