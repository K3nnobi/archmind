#!/usr/bin/env zsh

emulate -L zsh
setopt localoptions typesetsilent no_beep

typeset -g ARCHMIND_ROOT="${${(%):-%N}:A:h:h}"

typeset -g ARCHMIND_LOG_DIR="$HOME/ArchMind/Logs"
typeset -g ARCHMIND_RENDER_LOG="$ARCHMIND_LOG_DIR/render-errors.log"

mkdir -p "$ARCHMIND_LOG_DIR" 2>/dev/null || true

# A fast, read-only package baseline catches relevant updates performed outside
# ArchMind. It only records follow-up tasks; it never upgrades the system.
if (( $+commands[python3] )) && [[ -f "$ARCHMIND_ROOT/tools/update-guardian.py" ]]; then
    ARCHMIND_DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}" \
        python3 -B "$ARCHMIND_ROOT/tools/update-guardian.py" --baseline-only \
        >/dev/null 2>&1 || true
fi

source "$ARCHMIND_ROOT/core/afi/init.zsh"

afi_init || exit 1

typeset -g current_screen="home"
typeset -i selected=1
typeset -i running=1
typeset -i resize_requested=0

typeset -a menu_entries

archmind_console_cleanup() {
    afi_reset_terminal_state
    printf '\e[?1049l'
}

archmind_console_resize() {
    resize_requested=1
}

archmind_console_confirm_exit() {
    emulate -L zsh

    if afi_confirm_dialog \
        "Exit ArchMind" \
        "Return to the terminal and close ArchMind?" \
        54; then
        running=0
    fi
}

archmind_console_render() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local terminal_width=80
    local terminal_height=24
    local minimum_width=40
    local screen_column=2
    local right_margin=2
    local usable_width=0
    local total=0

    local current_entry=""
    local current_label=""
    local current_description=""
    local generated_entry=""

    local header_output=""
    local breadcrumb_output=""
    local menu_output=""
    local status_output=""
    local context_output=""
    local footer_output=""

    local workspace_row=9
    local context_row=0
    local footer_row=0

    local gap=3
    local left_width=0
    local right_width=0
    local status_column=0
    local status_height=14
    local menu_height=0
    local workspace_height=0
    local body_rows=0
    local max_visible=0
    local wide_layout=0
    local compact_layout=0
    local show_header=1
    local show_breadcrumb=0
    local show_context=0
    local tiny_output=""

    local -a menu_entries
    menu_entries=()

    # Load the selected screen and persistent settings.
    afi_load_screen "$current_screen"
    settings_load

    # Freeze one physical size for the complete frame. If another WINCH lands
    # while drawing, the next frame will refresh it atomically.
    afi_refresh_term_size
    terminal_width="$(afi_term_width)"
    terminal_height="$(afi_term_height)"

    [[ "$terminal_width" == <-> ]] || terminal_width=80
    [[ "$terminal_height" == <-> ]] || terminal_height=24

    minimum_width="${ARCHMIND_CONSOLE_MIN_WIDTH:-40}"
    [[ "$minimum_width" == <-> ]] || minimum_width=40
    (( minimum_width < 24 )) && minimum_width=24

    total=${#AFI_SCREEN_ENTRIES[@]}

    if (( total < 1 )); then
        return 1
    fi

    (( selected < 1 )) && selected=1
    (( selected > total )) && selected="$total"

    current_entry="${AFI_SCREEN_ENTRIES[$selected]}"
    current_label="$(afi_entry_label "$current_entry")"
    current_description="$(afi_entry_description "$current_entry")"

    while IFS= read -r generated_entry; do
        [[ -n "$generated_entry" ]] && \
            menu_entries+=("$generated_entry")
    done < <(afi_entries_for_menu)

    # Like full-screen TUIs such as btop, AFI switches to an explicit minimum
    # size notice instead of drawing panels outside a terminal that is too
    # small to represent them safely.
    if (( terminal_width < minimum_width || terminal_height < 8 )); then
        typeset -g AFI_LAYOUT_MODE="tiny"

        usable_width=$(( terminal_width - 1 ))
        (( usable_width < 1 )) && usable_width=1

        tiny_output="$(
            print -r -- "${AFI_PRIMARY}${AFI_BOLD}ARCHMIND${AFI_RESET}"
            print -r -- "Terminal: ${terminal_width} x ${terminal_height}"
            print -r -- "Minimum:  ${minimum_width} x 8"
            print -r -- "Enlarge the window to restore the interface."
            print -r -- "Q Exit"
        )"

        afi_disable_wrap
        afi_clear_screen
        afi_render_at 0 0 "$tiny_output"
        return 0
    fi

    screen_column="${ARCHMIND_CONSOLE_MARGIN:-2}"
    right_margin="${ARCHMIND_CONSOLE_MARGIN:-2}"

    [[ "$screen_column" == <-> ]] || screen_column=2
    [[ "$right_margin" == <-> ]] || right_margin=2

    (( screen_column < 0 )) && screen_column=0
    (( right_margin < 0 )) && right_margin=0

    # Correct arithmetic expansion.
    # One extra column remains unused to prevent terminal wrapping.
    usable_width=$(( terminal_width - screen_column - right_margin - 1 ))

    # Never invent more width than the terminal actually has.
    if (( usable_width < 20 )); then
        screen_column=0
        right_margin=0
        usable_width=$(( terminal_width - 1 ))
    fi

    (( usable_width < 4 )) && usable_width=4

    # Vertical breakpoints: full, standard and compact. All positions below
    # are derived from the current PTY dimensions on every frame.
    if (( terminal_height < 22 )); then
        compact_layout=1
        show_header=0
        workspace_row=0
        footer_row=$(( terminal_height - 1 ))
        body_rows="$footer_row"
        typeset -g AFI_LAYOUT_MODE="compact"
    else
        footer_row=$(( terminal_height - 3 ))
        show_breadcrumb=$(( terminal_height >= 28 ))
        workspace_row=5
        (( show_breadcrumb )) && workspace_row=9
        body_rows=$(( footer_row - workspace_row ))
        typeset -g AFI_LAYOUT_MODE="standard"
    fi

    (( body_rows < 5 )) && body_rows=5

    if (( usable_width >= 96 && body_rows >= 14 )); then
        wide_layout=1

        left_width=$(( usable_width * 46 / 100 ))
        right_width=$(( usable_width - left_width - gap ))

        # Keep both panels inside the available area.
        if (( left_width < 40 )); then
            left_width=40
        fi

        right_width=$(( usable_width - left_width - gap ))

        if (( right_width < 36 )); then
            wide_layout=0
        fi
    fi

    # Keep the full menu when possible; otherwise expose a moving window whose
    # scroll indicators follow the selected item.
    menu_height=$(( total + 4 ))
    workspace_height="$menu_height"
    (( wide_layout && status_height > workspace_height )) && \
        workspace_height="$status_height"

    if (( ! compact_layout && workspace_height + 6 <= body_rows )); then
        show_context=1
        context_row=$(( workspace_row + workspace_height + 1 ))
        typeset -g AFI_LAYOUT_MODE="full"
    else
        max_visible=$(( body_rows - 4 ))
        (( max_visible < 1 )) && max_visible=1
        (( max_visible > total )) && max_visible="$total"
        menu_height=$(( max_visible + 4 ))
        workspace_height="$menu_height"

        if (( wide_layout )); then
            (( status_height > body_rows )) && status_height="$body_rows"
            (( status_height > workspace_height )) && \
                workspace_height="$status_height"
        fi
    fi

    # Build every visible component before clearing the frame.
    if (( show_header )); then
        header_output="$(
            afi_header \
                "v2.1 Responsive" \
                "Arch Linux" \
                "$usable_width"
        )"
    fi

    if (( show_breadcrumb )); then
        breadcrumb_output="$(
            afi_breadcrumb \
                "$AFI_SCREEN_BREADCRUMB" \
                "$usable_width"
        )"
    fi

    if (( wide_layout )); then
        menu_output="$(
            afi_menu_render_window \
                "$AFI_SCREEN_TITLE" \
                "$left_width" \
                "$selected" \
                "$max_visible" \
                "${menu_entries[@]}"
        )"

        status_output="$(
            afi_status_panel \
                "$AFI_SCREEN_STATUS_TYPE" \
                "$right_width" \
                "$status_height"
        )"

        status_column=$(( screen_column + left_width + gap ))
    else
        menu_output="$(
            afi_menu_render_window \
                "$AFI_SCREEN_TITLE" \
                "$usable_width" \
                "$selected" \
                "$max_visible" \
                "${menu_entries[@]}"
        )"
    fi

    if (( show_context )); then
        context_output="$(
            afi_context_panel \
                "$current_label" \
                "$current_description" \
                "$usable_width"
        )"
    fi

    if (( compact_layout )); then
        footer_output="${AFI_MUTED}$(
            afi_fit_text \
                "  ↑↓ Navigate  Enter Select  Esc Back  Q Exit" \
                "$usable_width"
        )${AFI_RESET}"
    else
        footer_output="$(afi_footer "$usable_width")"
    fi

    # Draw one complete frame.
    afi_disable_wrap
    afi_clear_screen

    if (( show_header )); then
        afi_render_at \
            0 \
            "$screen_column" \
            "$header_output"
    fi

    if (( show_breadcrumb )); then
        afi_render_at \
            5 \
            "$screen_column" \
            "$breadcrumb_output"
    fi

    afi_render_at \
        "$workspace_row" \
        "$screen_column" \
        "$menu_output"

    if (( wide_layout )); then
        afi_render_at \
            "$workspace_row" \
            "$status_column" \
            "$status_output"
    fi

    if (( show_context )); then
        afi_render_at \
            "$context_row" \
            "$screen_column" \
            "$context_output"
    fi

    afi_render_at \
        "$footer_row" \
        "$screen_column" \
        "$footer_output"
}

archmind_console_activate_current() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local current_entry
    local current_label
    local current_action

    current_entry="${AFI_SCREEN_ENTRIES[$selected]}"
    current_label="$(afi_entry_label "$current_entry")"
    current_action="$(afi_entry_action "$current_entry")"

    case "$current_action" in
        system|backup|install|monitor|ai|git|python|settings|maintenance|doctor)
            current_screen="$current_action"
            selected=1
            ;;

        back)
            current_screen="home"
            selected=1
            ;;

        exit)
            archmind_console_confirm_exit
            ;;

        *)
            afi_dispatch_action "$current_action" "$current_label"
            ;;
    esac
}

archmind_console_back() {
    emulate -L zsh

    if [[ "$current_screen" == "home" ]]; then
        archmind_console_confirm_exit
    else
        current_screen="home"
        selected=1
    fi
}

archmind_console_run() {
    emulate -L zsh
    setopt localoptions typesetsilent no_beep

    # Start each session with an empty render-error log.
    : > "$ARCHMIND_RENDER_LOG"

    local total
    local key

    trap archmind_console_cleanup EXIT INT TERM HUP
    trap archmind_console_resize WINCH

    # Use the terminal alternate screen buffer.
    printf '\e[?1049h'
    afi_disable_wrap
    tput civis 2>/dev/null || true

    while (( running )); do
        resize_requested=0

        afi_load_screen "$current_screen"
        total=${#AFI_SCREEN_ENTRIES[@]}

        archmind_console_render 2>>"$ARCHMIND_RENDER_LOG"

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
                archmind_console_activate_current
                ;;

            escape)
                archmind_console_back
                ;;

            quit)
                archmind_console_confirm_exit
                ;;
        esac
    done
}

archmind_console_run
