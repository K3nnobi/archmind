#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/draw.zsh"

afi_footer() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local requested_width="${1:-full}"
    local width
    local inner
    local shortcuts
    local fitted

    shortcuts="  ↑↓ Navigate  │  Enter Select  │  Esc Back  │  Q Exit  "

    width="$(afi_resolve_width "$requested_width")"
    inner=$(( width - 2 ))
    fitted="$(afi_fit_text "$shortcuts" "$inner")"

    afi_border_top "$width"

    printf '%s│%s' "$AFI_PRIMARY" "$AFI_RESET"
    printf '%s%s%s' "$AFI_MUTED" "$fitted" "$AFI_RESET"
    printf '%s│%s\n' "$AFI_PRIMARY" "$AFI_RESET"

    afi_border_bottom "$width"
}
