#!/usr/bin/env zsh

emulate -L zsh
setopt localoptions typesetsilent

typeset -g BASE="${${(%):-%N}:A:h:h}"

source "$BASE/core/afi/header.zsh"
source "$BASE/core/afi/menu.zsh"
source "$BASE/core/afi/footer.zsh"
source "$BASE/core/afi/input.zsh"
source "$BASE/core/afi/workspace.zsh"
source "$BASE/core/afi/context.zsh"
source "$BASE/core/afi/status.zsh"
source "$BASE/core/afi/dialog.zsh"
source "$BASE/core/afi/screens.zsh"
source "$BASE/core/afi/breadcrumb.zsh"
source "$BASE/core/afi/actions.zsh"

typeset -g current_screen="home"
typeset -i selected=1
typeset -i running=1
typeset -a menu_entries

cleanup_console() {
    printf '%s' "$AFI_RESET"
    tput cnorm 2>/dev/null || true
    clear
}

trap cleanup_console EXIT INT TERM
tput civis 2>/dev/null || true

while (( running )); do
    afi_load_screen "$current_screen"

    terminal_width="$(afi_term_width)"
    terminal_height="$(afi_term_height)"

    screen_column=2
    usable_width=$(( terminal_width - 4 ))

    (( usable_width < 40 )) && usable_width=40

    total=${#AFI_SCREEN_ENTRIES[@]}

    (( selected < 1 )) && selected=1
    (( selected > total )) && selected="$total"

    current_entry="${AFI_SCREEN_ENTRIES[$selected]}"
    current_label="$(afi_entry_label "$current_entry")"
    current_description="$(afi_entry_description "$current_entry")"
    current_action="$(afi_entry_action "$current_entry")"

    menu_entries=()
    while IFS= read -r generated_entry; do
        menu_entries+=("$generated_entry")
    done < <(afi_entries_for_menu)

    afi_clear_screen

    header_output="$(
        afi_header \
            "v2.1 Responsive" \
            "Arch Linux" \
            "$usable_width"
    )"

    afi_render_at 1 "$screen_column" "$header_output"

    breadcrumb_output="$(
        afi_breadcrumb \
            "$AFI_SCREEN_BREADCRUMB" \
            "$usable_width"
    )"

    afi_render_at 5 "$screen_column" "$breadcrumb_output"

    workspace_row=9

    if (( usable_width >= 96 )); then
        gap=3
        left_width=$(( usable_width * 47 / 100 ))
        right_width=$(( usable_width - left_width - gap ))

        (( left_width < 42 )) && left_width=42
        (( right_width < 40 )) && right_width=40

        if (( left_width + gap + right_width > usable_width )); then
            right_width=$(( usable_width - left_width - gap ))
        fi

        menu_output="$(
            afi_menu_render \
                "$AFI_SCREEN_TITLE" \
                "$left_width" \
                "$selected" \
                "${menu_entries[@]}"
        )"

        status_output="$(
            afi_status_panel \
                "$AFI_SCREEN_STATUS_TYPE" \
                "$right_width" \
                14
        )"

        afi_render_at "$workspace_row" "$screen_column" "$menu_output"

        status_column=$(( screen_column + left_width + gap ))
        afi_render_at "$workspace_row" "$status_column" "$status_output"

        context_row=$(( workspace_row + 15 ))

        context_output="$(
            afi_context_panel \
                "$current_label" \
                "$current_description" \
                "$usable_width"
        )"

        afi_render_at "$context_row" "$screen_column" "$context_output"
    else
        menu_output="$(
            afi_menu_render \
                "$AFI_SCREEN_TITLE" \
                "$usable_width" \
                "$selected" \
                "${menu_entries[@]}"
        )"

        afi_render_at "$workspace_row" "$screen_column" "$menu_output"

        context_row=$(( workspace_row + total + 4 ))

        context_output="$(
            afi_context_panel \
                "$current_label" \
                "$current_description" \
                "$usable_width"
        )"

        afi_render_at "$context_row" "$screen_column" "$context_output"
    fi

    footer_output="$(afi_footer "$usable_width")"
    footer_row=$(( terminal_height - 4 ))

    (( footer_row < 30 )) && footer_row=30

    afi_render_at "$footer_row" "$screen_column" "$footer_output"

    afi_read_key
    key="$REPLY"

    case "$key" in
        up)
            (( selected-- ))
            (( selected < 1 )) && selected="$total"
            ;;

        down)
            (( selected++ ))
            (( selected > total )) && selected=1
            ;;

        enter)
            case "$current_action" in
                system|backup|install|monitor|ai|git|python|settings|doctor)
                    current_screen="$current_action"
                    selected=1
                    ;;

                back)
                    current_screen="home"
                    selected=1
                    ;;

                exit)
                    if afi_confirm_dialog \
                        "Exit ArchMind" \
                        "Do you really want to return to the terminal?" \
                        54; then
                        running=0
                    fi
                    ;;

                *)
                    afi_dispatch_action "$current_action" "$current_label"
                    ;;
            esac
            ;;

        escape)
            if [[ "$current_screen" == "home" ]]; then
                if afi_confirm_dialog \
                    "Exit ArchMind" \
                    "Do you really want to return to the terminal?" \
                    54; then
                    running=0
                fi
            else
                current_screen="home"
                selected=1
            fi
            ;;

        quit)
            if afi_confirm_dialog \
                "Exit ArchMind" \
                "Do you really want to return to the terminal?" \
                54; then
                running=0
            fi
            ;;
    esac
done
