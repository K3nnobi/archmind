#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/panel.zsh"
source "$AFI_ROOT/input.zsh"
source "$AFI_ROOT/workspace.zsh"

afi_confirm_dialog() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local title="${1:-Confirm}"
    local message="${2:-Continue with this operation?}"
    local requested_width="${3:-52}"
    local dialog_width=52
    local terminal_width
    local terminal_height
    local dialog_column
    local dialog_row
    local output
    local key

    while true; do
        resize_requested=0
        afi_refresh_term_size
        terminal_width="$(afi_term_width)"
        terminal_height="$(afi_term_height)"
        dialog_width="$requested_width"

        if (( terminal_width < 30 || terminal_height < 7 )); then
            local compact_width=$(( terminal_width - 1 ))
            (( compact_width < 1 )) && compact_width=1
            output="$(
                afi_fit_text "$title" "$compact_width"
                print
                afi_fit_text "$message" "$compact_width"
                print
                afi_fit_text "Enter Confirm | Esc Cancel" "$compact_width"
            )"
            dialog_column=0
            dialog_row=0
        else
            (( dialog_width > terminal_width - 4 )) && \
                dialog_width=$(( terminal_width - 4 ))
            (( dialog_width < 30 )) && dialog_width=30

            dialog_column=$(( (terminal_width - dialog_width) / 2 ))
            dialog_row=$(( (terminal_height - 7) / 2 ))

            output="$(
                afi_panel \
                    --title "$title" \
                    --width "$dialog_width" \
                    --height 7 \
                    --padding 2 \
                    "" \
                    "$message" \
                    "" \
                    "[Enter] Confirm     [Esc] Cancel"
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

            enter)
                return 0
                ;;

            escape|quit)
                return 1
                ;;
        esac
    done
}
