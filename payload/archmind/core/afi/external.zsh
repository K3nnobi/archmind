#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/palette.zsh"

afi_suspend_console() {
    emulate -L zsh

    printf '%s' "$AFI_RESET"
    afi_enable_wrap
    tput cnorm 2>/dev/null || true
    printf '\e[?1049l'
}

afi_resume_console() {
    emulate -L zsh

    printf '\e[?1049h'
    afi_disable_wrap
    clear
    tput civis 2>/dev/null || true
}

afi_run_external() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local command_function="${1:-}"

    [[ -n "$command_function" ]] || return 1
    (( $+functions[$command_function] )) || return 1

    afi_suspend_console

    "$command_function"
    local result=$?

    print
    print -r -- "Press Enter to return to ArchMind Console..."
    read -r

    afi_resume_console

    return "$result"
}
