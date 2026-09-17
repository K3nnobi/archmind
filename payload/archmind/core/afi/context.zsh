#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/panel.zsh"

afi_context_panel() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local label="${1:-No selection}"
    local description="${2:-No description available.}"
    local width="${3:-full}"

    afi_panel \
        --title "Information" \
        --width "$width" \
        --height 5 \
        --padding 2 \
        "Selected: ${label}" \
        "" \
        "${description}"
}
