#!/usr/bin/env zsh

typeset -gi AFI_TERM_WIDTH_CACHE=0
typeset -gi AFI_TERM_HEIGHT_CACHE=0

afi_refresh_term_size() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local terminal_size=""
    local width=""
    local height=""

    # Read /dev/tty explicitly. Some render loops use a here-string as stdin;
    # tput would then silently fall back to the terminfo default (often 80x24)
    # in the middle of the same frame.
    terminal_size="$(stty size </dev/tty 2>/dev/null)" || terminal_size=""

    if [[ "$terminal_size" == <->' '<-> ]]; then
        height="${terminal_size%% *}"
        width="${terminal_size##* }"
    else
        width="$(tput cols 2>/dev/null)" || width="${COLUMNS:-80}"
        height="$(tput lines 2>/dev/null)" || height="${LINES:-24}"
    fi

    [[ "$width" == <-> ]] || width="${COLUMNS:-80}"
    [[ "$height" == <-> ]] || height="${LINES:-24}"
    [[ "$width" == <-> ]] || width=80
    [[ "$height" == <-> ]] || height=24

    (( width < 1 )) && width=1
    (( height < 1 )) && height=1

    typeset -gi AFI_TERM_WIDTH_CACHE="$width"
    typeset -gi AFI_TERM_HEIGHT_CACHE="$height"

    REPLY="${height} ${width}"
}

afi_term_width() {
    emulate -L zsh
    setopt localoptions typesetsilent

    (( AFI_TERM_WIDTH_CACHE > 0 )) || afi_refresh_term_size
    print -r -- "$AFI_TERM_WIDTH_CACHE"
}

afi_term_height() {
    emulate -L zsh
    setopt localoptions typesetsilent

    (( AFI_TERM_HEIGHT_CACHE > 0 )) || afi_refresh_term_size
    print -r -- "$AFI_TERM_HEIGHT_CACHE"
}

afi_resolve_width() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local requested="${1:-full}"
    local terminal_width
    local width

    terminal_width="$(afi_term_width)"

    case "$requested" in
        full)
            width="$terminal_width"
            ;;

        auto)
            width=50
            ;;

        *%)
            local percentage="${requested%\%}"

            if [[ "$percentage" == <-> ]]; then
                width=$(( terminal_width * percentage / 100 ))
            else
                width="$terminal_width"
            fi
            ;;

        <->)
            width="$requested"
            ;;

        *)
            width="$terminal_width"
            ;;
    esac

    # Panels need four columns for two borders and useful content, but the
    # resolver must never return a width larger than the real terminal.
    if (( terminal_width >= 4 && width < 4 )); then
        width=4
    fi
    (( width > terminal_width )) && width="$terminal_width"

    print -r -- "$width"
}
