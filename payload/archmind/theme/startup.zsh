# ==========================================
# ArchMind Startup Interface
# Intelligence meets Linux
# ==========================================

_archmind_startup_ollama_status() {
    if command -v ollama >/dev/null 2>&1; then
        if pgrep -x ollama >/dev/null 2>&1; then
            print -P "%F{${ARCHMIND_COLOR_SUCCESS:-84}}${ARCHMIND_ICON_SUCCESS} Online%f"
        else
            print -P "%F{${ARCHMIND_COLOR_WARNING:-221}}${ARCHMIND_ICON_WARNING} Offline%f"
        fi
    else
        print -P "%F{${ARCHMIND_COLOR_MUTED:-245}}Not installed%f"
    fi
}

_archmind_startup_battery() {
    local battery=(/sys/class/power_supply/BAT*(N))

    if (( ${#battery[@]} == 0 )); then
        print -r -- "Unavailable"
        return
    fi

    local capacity="?"
    local status=""

    [[ -r "${battery[1]}/capacity" ]] &&
        capacity="$(<"${battery[1]}/capacity")"

    [[ -r "${battery[1]}/status" ]] &&
        status="$(<"${battery[1]}/status")"

    print -r -- "${capacity}% — ${status}"
}

_archmind_startup_repeat() {
    local character="$1"
    local count="$2"
    local result=""

    while (( count-- > 0 )); do
        result+="$character"
    done

    REPLY="$result"
}

_archmind_startup_max_width() {
    local text
    local maximum=0

    for text in "$@"; do
        (( ${#text} > maximum )) && maximum=${#text}
    done

    REPLY="$maximum"
}

_archmind_startup_box_row() {
    local text="$1"
    local width="$2"
    local color="${3:-}"
    local reset="${4:-}"

    (( ${#text} > width )) && text="${text[1,width]}"
    printf -v REPLY '%s│ %-*s │%s' "$color" "$width" "$text" "$reset"
}

_archmind_startup_fastfetch() {
    local output=""
    local line key value
    local -a raw_lines=()

    command -v fastfetch >/dev/null 2>&1 || return 1

    output="$(
        fastfetch \
            --config none \
            --logo none \
            --pipe \
            --key-width 0 \
            --separator '::' \
            --structure 'OS:Kernel:Uptime:Packages:Shell:DE:WM:Terminal:Memory:CPU:GPU:Display' \
            2>/dev/null
    )" || return 1

    [[ -n "$output" ]] || return 1

    # Some Fastfetch versions may still emit control sequences to align keys
    # and values. Inside a panel, these sequences move the cursor and corrupt
    # the ArchMind panel by moving the cursor to an absolute column.
    # Remove CSI/OSC and other controls before measuring or drawing lines.
    output="$(
        print -rn -- "$output" \
            | LC_ALL=C sed -E $'s~\x1B\\[[0-?]*[ -/]*[@-~]~~g; s~\x1B\\][^\x07]*(\x07|\x1B\\\\)~~g' \
            | LC_ALL=C tr '\t' ' ' \
            | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177'
    )"

    [[ -n "$output" ]] || return 1
    raw_lines=("${(@f)output}")
    reply=()

    for line in "${raw_lines[@]}"; do
        if [[ "$line" == *::* ]]; then
            key="${line%%::*}"
            value="${line#*::}"

            while [[ "$key" == ' '* ]]; do key="${key# }"; done
            while [[ "$key" == *' ' ]]; do key="${key% }"; done
            while [[ "$value" == ' '* ]]; do value="${value# }"; done
            while [[ "$value" == *' ' ]]; do value="${value% }"; done

            printf -v line '%-9.9s %s' "$key" "$value"
        fi

        reply+=("$line")
    done

    (( ${#reply[@]} > 0 ))
}

archmind_startup() {
    [[ "${ARCHMIND_STARTUP_ENABLED:-true}" != "true" ]] && return 0

    # Avoid repeating the panel in subshells.
    [[ -n "${ARCHMIND_STARTUP_SHOWN:-}" ]] && return 0
    export ARCHMIND_STARTUP_SHOWN="true"

    [[ "${ARCHMIND_STARTUP_CLEAR:-false}" == "true" ]] && clear

    local host_name="${HOST:-$(hostname)}"
    local kernel="$(uname -r)"
    local memory=""
    local uptime_text=""
    local battery_text=""
    local ollama_text=""
    local term_width="${COLUMNS:-0}"
    local left_inner=0
    local right_inner=0
    local maximum_inner=0
    local combined_width=0
    local side_by_side=false
    local cyan accent muted text_color reset bold
    local left_rule right_rule
    local index max_lines
    local left_title left_subtitle left_section_system
    local left_host left_kernel left_memory left_uptime left_battery
    local left_section_neural left_ollama left_model left_command
    local right_title="FASTFETCH"
    local right_subtitle="Compact system overview"
    local -a left_lines=()
    local -a right_lines=()
    local -a left_texts=()
    local -a right_texts=()
    local -a fastfetch_lines=()
    local -a reply=()

    # The output of free changes with the system language (Mem:, Mem.:, etc.).
    # Forcing C keeps collection reliable without changing the session locale.
    memory="$(LC_ALL=C free -h 2>/dev/null | awk '/^Mem:/ {print $3 " / " $2}')"
    uptime_text="$(uptime -p 2>/dev/null | sed 's/^up //')"
    battery_text="$(_archmind_startup_battery)"

    if command -v ollama >/dev/null 2>&1; then
        if pgrep -x ollama >/dev/null 2>&1; then
            ollama_text="Online"
        else
            ollama_text="Offline"
        fi
    else
        ollama_text="Not installed"
    fi

    (( term_width > 0 )) || term_width="$(tput cols 2>/dev/null || print 80)"

    left_title="ARCHMIND ${ARCHMIND_VERSION:-0.1.0}"
    left_subtitle="Intelligence meets Linux"
    left_section_system="SYSTEM MATRIX"
    left_host="Host      ${host_name}"
    left_kernel="Kernel    ${kernel}"
    left_memory="Memory    ${memory:-unavailable}"
    left_uptime="Uptime    ${uptime_text:-unavailable}"
    left_battery="Battery   ${battery_text}"
    left_section_neural="NEURAL CORE"
    left_ollama="Ollama    ${ollama_text}"
    left_model="Model     ${ARCHMIND_AI_DEFAULT_MODEL:-qwen2.5-coder:7b}"
    left_command="Command   archmind-console"
    left_texts=(
        "$left_title" "$left_subtitle" "$left_section_system"
        "$left_host" "$left_kernel" "$left_memory" "$left_uptime"
        "$left_battery" "$left_section_neural" "$left_ollama"
        "$left_model" "$left_command"
    )

    if [[ "${ARCHMIND_STARTUP_FASTFETCH:-false}" == "true" ]] &&
       _archmind_startup_fastfetch; then
        fastfetch_lines=("${reply[@]}")
        right_texts=("$right_title" "$right_subtitle")
        for index in {1..12}; do
            right_texts+=("${fastfetch_lines[index]:-}")
        done
    fi

    _archmind_startup_max_width "${left_texts[@]}"
    left_inner="$REPLY"

    if (( ${#right_texts[@]} > 0 )); then
        _archmind_startup_max_width "${right_texts[@]}"
        right_inner="$REPLY"
        combined_width=$(( left_inner + right_inner + 10 ))
        (( combined_width < term_width )) && side_by_side=true
    fi

    # In stacked mode, limit only the panel that would exceed the window.
    # A box occupies its inner width plus four characters (walls and margins).
    if [[ "$side_by_side" != "true" ]]; then
        maximum_inner=$(( term_width > 9 ? term_width - 5 : 8 ))
        (( left_inner > maximum_inner )) && left_inner=$maximum_inner
        (( right_inner > maximum_inner )) && right_inner=$maximum_inner
    fi

    cyan="$(print -Pn "%F{${ARCHMIND_COLOR_SECONDARY:-45}}")"
    accent="$(print -Pn "%F{${ARCHMIND_COLOR_ACCENT:-99}}")"
    muted="$(print -Pn "%F{${ARCHMIND_COLOR_MUTED:-245}}")"
    text_color="$(print -Pn "%F{${ARCHMIND_COLOR_TEXT:-255}}")"
    reset="$(print -Pn '%f%b')"
    bold="$(print -Pn '%B')"

    # Panel walls are calculated from each panel's longest sentence. Lines also
    # include one inner space on each side, which is included in the ruler.
    _archmind_startup_repeat '─' "$(( left_inner + 2 ))"
    left_rule="$REPLY"
    _archmind_startup_repeat '─' "$(( right_inner + 2 ))"
    right_rule="$REPLY"

    left_lines+=("${cyan}╭${left_rule}╮${reset}")
    _archmind_startup_box_row "$left_title" "$left_inner" "${cyan}${bold}" "$reset"
    left_lines+=("$REPLY")
    _archmind_startup_box_row "$left_subtitle" "$left_inner" "$muted" "$reset"
    left_lines+=("$REPLY" "${cyan}├${left_rule}┤${reset}")
    _archmind_startup_box_row "$left_section_system" "$left_inner" "${accent}${bold}" "$reset"
    left_lines+=("$REPLY")
    _archmind_startup_box_row "$left_host" "$left_inner" "$text_color" "$reset"
    left_lines+=("$REPLY")
    _archmind_startup_box_row "$left_kernel" "$left_inner" "$text_color" "$reset"
    left_lines+=("$REPLY")
    _archmind_startup_box_row "$left_memory" "$left_inner" "$text_color" "$reset"
    left_lines+=("$REPLY")
    _archmind_startup_box_row "$left_uptime" "$left_inner" "$text_color" "$reset"
    left_lines+=("$REPLY")
    _archmind_startup_box_row "$left_battery" "$left_inner" "$text_color" "$reset"
    left_lines+=("$REPLY" "${cyan}├${left_rule}┤${reset}")
    _archmind_startup_box_row "$left_section_neural" "$left_inner" "${accent}${bold}" "$reset"
    left_lines+=("$REPLY")
    _archmind_startup_box_row "$left_ollama" "$left_inner" "$text_color" "$reset"
    left_lines+=("$REPLY")
    _archmind_startup_box_row "$left_model" "$left_inner" "$text_color" "$reset"
    left_lines+=("$REPLY" "${cyan}├${left_rule}┤${reset}")
    _archmind_startup_box_row "$left_command" "$left_inner" "$muted" "$reset"
    left_lines+=("$REPLY" "${cyan}╰${left_rule}╯${reset}")

    if (( ${#right_texts[@]} > 0 )); then
        right_lines+=("${cyan}╭${right_rule}╮${reset}")
        _archmind_startup_box_row "$right_title" "$right_inner" "${cyan}${bold}" "$reset"
        right_lines+=("$REPLY")
        _archmind_startup_box_row "$right_subtitle" "$right_inner" "$muted" "$reset"
        right_lines+=("$REPLY" "${cyan}├${right_rule}┤${reset}")

        for index in {1..12}; do
            _archmind_startup_box_row "${fastfetch_lines[index]:-}" "$right_inner" "$text_color" "$reset"
            right_lines+=("$REPLY")
        done

        right_lines+=("${cyan}╰${right_rule}╯${reset}")
    fi

    echo
    if (( ${#right_lines[@]} > 0 )) && [[ "$side_by_side" == "true" ]]; then
        max_lines=$(( ${#left_lines[@]} > ${#right_lines[@]} ? ${#left_lines[@]} : ${#right_lines[@]} ))
        for (( index = 1; index <= max_lines; index++ )); do
            print -r -- "${left_lines[index]:-}  ${right_lines[index]:-}"
        done
    else
        print -rl -- "${left_lines[@]}"
        if (( ${#right_lines[@]} > 0 )); then
            echo
            print -rl -- "${right_lines[@]}"
        fi
    fi
    echo
}

# Run only in interactive terminals.
if [[ -o interactive ]]; then
    archmind_startup
fi
