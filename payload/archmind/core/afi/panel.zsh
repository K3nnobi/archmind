#!/usr/bin/env zsh

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"

source "$AFI_ROOT/draw.zsh"

afi_panel() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local title="PANEL"
    local requested_width="50%"
    local requested_height=0
    local padding=1
    local argument=""
    local source_line=""
    local current_line=""
    local longest=0
    local width=0
    local terminal_width=0
    local inner=0
    local content_width=0
    local content_rows=0
    local title_label=""
    local title_length=0
    local remaining=0
    local fitted=""
    local used_rows=0

    local -a raw_lines
    local -a lines

    raw_lines=()
    lines=()

    while (( $# > 0 )); do
        argument="$1"

        case "$argument" in
            --title)
                (( $# >= 2 )) || {
                    print -u2 -- "afi_panel: missing value after --title"
                    return 1
                }

                title="$2"
                shift 2
                ;;

            --width)
                (( $# >= 2 )) || {
                    print -u2 -- "afi_panel: missing value after --width"
                    return 1
                }

                requested_width="$2"
                shift 2
                ;;

            --height)
                (( $# >= 2 )) || {
                    print -u2 -- "afi_panel: missing value after --height"
                    return 1
                }

                requested_height="$2"
                shift 2
                ;;

            --padding)
                (( $# >= 2 )) || {
                    print -u2 -- "afi_panel: missing value after --padding"
                    return 1
                }

                padding="$2"
                shift 2
                ;;

            --)
                shift
                raw_lines+=("$@")
                break
                ;;

            *)
                raw_lines+=("$argument")
                shift
                ;;
        esac
    done

    [[ "$padding" == <-> ]] || padding=1
    [[ "$requested_height" == <-> ]] || requested_height=0

    (( padding < 0 )) && padding=0
    (( padding > 4 )) && padding=4

    # Normalize multiline arguments into independent panel rows.
    for source_line in "${raw_lines[@]}"; do
        if [[ "$source_line" == *$'\n'* ]]; then
            while IFS= read -r current_line; do
                lines+=("$current_line")
            done <<< "$source_line"
        else
            lines+=("$source_line")
        fi
    done

    (( ${#lines[@]} == 0 )) && lines+=("")

    terminal_width="$(afi_term_width)"

    # Below four columns a bordered panel cannot be represented safely.
    # Callers use a plain compact notice for such terminal sizes.
    (( terminal_width < 4 )) && return 0

    if [[ "$requested_width" == "auto" ]]; then
        longest="$(afi_visible_length "$title")"

        for current_line in "${lines[@]}"; do
            local current_length
            current_length="$(afi_visible_length "$current_line")"

            (( current_length > longest )) && longest="$current_length"
        done

        width=$(( longest + padding * 2 + 2 ))

        (( width < 28 && terminal_width >= 28 )) && width=28
        (( width > terminal_width )) && width="$terminal_width"
    else
        width="$(afi_resolve_width "$requested_width")"
    fi

    inner=$(( width - 2 ))
    content_width=$(( inner - padding * 2 ))

    (( content_width < 1 )) && content_width=1

    if (( requested_height >= 3 )); then
        content_rows=$(( requested_height - 2 ))
    else
        content_rows=${#lines[@]}
        (( content_rows < 1 )) && content_rows=1
    fi

    title_label=" ${title:u} "
    title_length="$(afi_visible_length "$title_label")"

    # Keep the title inside the top border.
    if (( title_length > inner - 2 )); then
        title_label=" $(afi_truncate_text "${title:u}" $(( inner - 4 ))) "
        title_length="$(afi_visible_length "$title_label")"
    fi

    remaining=$(( inner - title_length - 1 ))
    (( remaining < 0 )) && remaining=0

    printf '%s┌─%s%s%s' \
        "$AFI_PRIMARY" \
        "$AFI_SECONDARY$AFI_BOLD" \
        "$title_label" \
        "$AFI_PRIMARY"

    afi_repeat "─" "$remaining"
    printf '┐%s\n' "$AFI_RESET"

    used_rows=0

    for current_line in "${lines[@]}"; do
        (( used_rows >= content_rows )) && break

        fitted="$(afi_fit_text "$current_line" "$content_width")"

        printf '%s│%s' "$AFI_PRIMARY" "$AFI_RESET"
        afi_spaces "$padding"
        printf '%s%s%s' "$AFI_TEXT" "$fitted" "$AFI_RESET"
        afi_spaces "$padding"
        printf '%s│%s\n' "$AFI_PRIMARY" "$AFI_RESET"

        (( used_rows++ ))
    done

    while (( used_rows < content_rows )); do
        printf '%s│%s' "$AFI_PRIMARY" "$AFI_RESET"
        afi_spaces "$inner"
        printf '%s│%s\n' "$AFI_PRIMARY" "$AFI_RESET"

        (( used_rows++ ))
    done

    printf '%s└' "$AFI_PRIMARY"
    afi_repeat "─" "$inner"
    printf '┘%s\n' "$AFI_RESET"
}
