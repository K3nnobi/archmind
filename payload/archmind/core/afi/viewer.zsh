#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/panel.zsh"
source "$AFI_ROOT/input.zsh"
source "$AFI_ROOT/workspace.zsh"

afi_viewer() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local title="${1:-Information}"
    shift

    local terminal_width
    local terminal_height
    local viewer_width
    local viewer_height
    local viewer_column
    local viewer_row
    local max_content_rows
    local source_line
    local current_line
    local output
    local key
    local index

    local -a content_lines
    local -a display_lines
    local -a render_lines
    local -a clipped_lines

    content_lines=("$@")
    display_lines=()

    # Convert multiline arguments into real panel rows. This makes the height
    # independent from how each service assembled its result array.
    for source_line in "${content_lines[@]}"; do
        if [[ "$source_line" == *$'\n'* ]]; then
            while IFS= read -r current_line; do
                display_lines+=("$current_line")
            done <<< "$source_line"
        else
            display_lines+=("$source_line")
        fi
    done

    # Do not let trailing empty values create a gap above the return hint.
    while (( ${#display_lines[@]} > 0 )) && \
          [[ -z "${display_lines[-1]}" ]]; do
        display_lines[-1]=()
    done

    while true; do
        resize_requested=0
        afi_refresh_term_size
        terminal_width="$(afi_term_width)"
        terminal_height="$(afi_term_height)"
        render_lines=("${display_lines[@]}")

        if (( terminal_width < 24 || terminal_height < 6 )); then
            local compact_width=$(( terminal_width - 1 ))
            (( compact_width < 1 )) && compact_width=1
            output="$(
                afi_fit_text "$title" "$compact_width"
                print
                if (( ${#render_lines[@]} > 0 )); then
                    afi_fit_text "${render_lines[1]}" "$compact_width"
                    print
                fi
                afi_fit_text "Enter/Esc Back" "$compact_width"
            )"
            viewer_column=0
            viewer_row=0
            viewer_height=0
        else
            viewer_width=$(( terminal_width * 72 / 100 ))
            (( viewer_width < 54 && terminal_width >= 58 )) && viewer_width=54
            (( viewer_width > terminal_width - 4 )) && \
                viewer_width=$(( terminal_width - 4 ))
            (( viewer_width < 20 )) && viewer_width=$(( terminal_width - 2 ))

            # Keep the return hint visible while clipping only the rendered
            # copy; the complete source is reused after every resize.
            max_content_rows=$(( terminal_height - 6 ))
            (( max_content_rows < 1 )) && max_content_rows=1

            if (( ${#render_lines[@]} >= max_content_rows )); then
                if (( max_content_rows > 1 )); then
                    clipped_lines=()
                    for (( index = 1; \
                           index < max_content_rows; \
                           index++ )); do
                        clipped_lines+=("${render_lines[$index]}")
                    done
                    clipped_lines+=("[Enter/Esc] Back")
                    render_lines=("${clipped_lines[@]}")
                else
                    render_lines=("[Enter/Esc] Back")
                fi
            else
                render_lines+=("[Enter/Esc] Back")
            fi

            viewer_height=$(( ${#render_lines[@]} + 2 ))
            viewer_column=$(( (terminal_width - viewer_width) / 2 ))
            viewer_row=$(( (terminal_height - viewer_height) / 2 ))

            output="$(
                afi_panel \
                    --title "$title" \
                    --width "$viewer_width" \
                    --height "$viewer_height" \
                    --padding 2 \
                    "${render_lines[@]}"
            )"
        fi

        afi_clear_screen
        afi_render_at "$viewer_row" "$viewer_column" "$output"

        if (( viewer_height >= 3 )); then
            afi_cursor_move $(( viewer_row + viewer_height - 1 )) "$viewer_column"
            afi_border_bottom "$viewer_width"
        fi

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
