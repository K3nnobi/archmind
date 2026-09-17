#!/usr/bin/env zsh

# ArchMind Framework Interface — Official palette
[[ -n ${AFI_PALETTE_LOADED:-} ]] && return 0
typeset -gr AFI_PALETTE_LOADED=1

typeset -gr AFI_RESET=$'\e[0m'
typeset -gr AFI_BOLD=$'\e[1m'

typeset -gr AFI_PRIMARY=$'\e[38;5;39m'
typeset -gr AFI_SECONDARY=$'\e[38;5;45m'

typeset -gr AFI_TEXT=$'\e[38;5;255m'
typeset -gr AFI_MUTED=$'\e[38;5;250m'
typeset -gr AFI_DIM=$'\e[38;5;243m'

typeset -gr AFI_SUCCESS=$'\e[38;5;42m'
typeset -gr AFI_WARNING=$'\e[38;5;220m'
typeset -gr AFI_DANGER=$'\e[38;5;203m'
