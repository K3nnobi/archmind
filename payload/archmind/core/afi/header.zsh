#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/draw.zsh"

afi_header() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local version="${1:-v2.1 Responsive}"
    local system_name="${2:-Arch Linux}"
    local requested_width="${3:-full}"
    local width

    width="$(afi_resolve_width "$requested_width")"

    afi_border_top "$width"

    afi_row_lr \
        "  ▲ ARCHMIND" \
        "${version}  " \
        "$width" \
        "${AFI_PRIMARY}${AFI_BOLD}" \
        "$AFI_SECONDARY"

    afi_row_lr \
        "  Intelligent Arch Linux Management Platform" \
        "${system_name}  " \
        "$width" \
        "$AFI_MUTED" \
        "$AFI_MUTED"

    afi_border_bottom "$width"
}
