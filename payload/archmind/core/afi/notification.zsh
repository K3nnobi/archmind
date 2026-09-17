#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/panel.zsh"
source "$AFI_ROOT/input.zsh"
source "$AFI_ROOT/workspace.zsh"

afi_notification() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local type="${1:-info}"
    local title="${2:-Information}"
    local message="${3:-}"
    local requested_width="${4:-58}"
    local dialog_width=58

    local terminal_width
    local terminal_height
    local dialog_column
    local dialog_row
    local color
    local symbol
    local output
    local key

    case "$type" in
        success)
            color="$AFI_SUCCESS"
            symbol="✓"
            ;;

        warning)
            color="$AFI_WARNING"
            symbol="⚠"
            ;;

        error)
            color="$AFI_DANGER"
            symbol="✗"
            ;;

        *)
            color="$AFI_SECONDARY"
            symbol="ℹ"
            ;;
    esac

    while true; do
        resize_requested=0
        afi_refresh_term_size
        terminal_width="$(afi_term_width)"
        terminal_height="$(afi_term_height)"
        dialog_width="$requested_width"

        if (( terminal_width < 32 || terminal_height < 8 )); then
            local compact_width=$(( terminal_width - 1 ))
            (( compact_width < 1 )) && compact_width=1
            output="$(
                afi_fit_text "$title" "$compact_width"
                print
                afi_fit_text "${symbol} ${message}" "$compact_width"
                print
                afi_fit_text "Enter/Esc Close" "$compact_width"
            )"
            dialog_column=0
            dialog_row=0
        else
            (( dialog_width > terminal_width - 4 )) && \
                dialog_width=$(( terminal_width - 4 ))
            (( dialog_width < 32 )) && dialog_width=32

            dialog_column=$(( (terminal_width - dialog_width) / 2 ))
            dialog_row=$(( (terminal_height - 8) / 2 ))

            output="$(
                afi_panel \
                    --title "$title" \
                    --width "$dialog_width" \
                    --height 8 \
                    --padding 2 \
                    "" \
                    "${color}${symbol}${AFI_RESET} ${message}" \
                    "" \
                    "[Enter/Esc] Close"
            )"
        fi

        afi_clear_screen
        afi_render_at "$dialog_row" "$dialog_column" "$output"

        afi_read_key
        key="$REPLY"

        case "$key" in
            resize)
                continue
                ;;

            enter|escape|quit)
                return 0
                ;;
        esac
    done
}
