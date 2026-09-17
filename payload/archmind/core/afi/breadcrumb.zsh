#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/panel.zsh"

afi_breadcrumb() {
    emulate -L zsh
    setopt localoptions typesetsilent

    # `path` is a special Zsh parameter tied to PATH.  Shadowing it here
    # prevents nested helpers from finding commands such as tput and sed.
    local breadcrumb_text="${1:-Home}"
    local width="${2:-full}"

    afi_panel \
        --title "Location" \
        --width "$width" \
        --height 3 \
        --padding 2 \
        "$breadcrumb_text"
}
