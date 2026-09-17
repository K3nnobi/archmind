#!/usr/bin/env zsh

afi_read_key() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local first=""
    local remaining=""
    local poll_interval="${AFI_INPUT_POLL_INTERVAL:-0.10}"
    local expected_width="$(afi_term_width)"
    local expected_height="$(afi_term_height)"
    local current_size=""
    local current_height=""
    local current_width=""

    # A blocking read prevented WINCH from redrawing AFI until the user pressed
    # a key. Polling at a low frequency keeps the console idle while allowing a
    # resize request to become an input event in at most about 100 ms.
    while true; do
        if (( ${+resize_requested} && resize_requested )); then
            REPLY="resize"
            return 0
        fi

        first=""
        if IFS= read -rs -k1 -t "$poll_interval" first 2>/dev/null; then
            break
        fi

        # Non-interactive Zsh can defer a WINCH trap while the read builtin is
        # active. Querying the PTY after each timeout makes resize detection
        # independent from that behavior and works across GNOME Terminal,
        # Kitty, Alacritty, WezTerm and Konsole.
        current_size="$(stty size 2>/dev/null)" || current_size=""
        if [[ "$current_size" == <->' '<-> ]]; then
            current_height="${current_size%% *}"
            current_width="${current_size##* }"

            if (( current_width != expected_width || \
                  current_height != expected_height )); then
                (( ${+resize_requested} )) && resize_requested=1
                REPLY="resize"
                return 0
            fi
        fi
    done

    case "$first" in
        $'\e')
            # Try to read the remaining arrow-key characters.
            IFS= read -rs -k2 -t 0.08 remaining 2>/dev/null || true

            case "${first}${remaining}" in
                $'\e[A') REPLY="up" ;;
                $'\e[B') REPLY="down" ;;
                $'\e[C') REPLY="right" ;;
                $'\e[D') REPLY="left" ;;
                *)       REPLY="escape" ;;
            esac
            ;;

        $'\r'|$'\n')
            REPLY="enter"
            ;;

        q|Q)
            REPLY="quit"
            ;;

        *)
            REPLY="other"
            ;;
    esac
}
