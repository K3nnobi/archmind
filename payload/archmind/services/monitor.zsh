#!/usr/bin/env zsh

monitor_cpu_model() {
    emulate -L zsh

    awk -F': ' '/model name/ {
        print $2
        exit
    }' /proc/cpuinfo 2>/dev/null || print -r -- "Unavailable"
}

monitor_cpu_usage() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local cpu user nice system idle iowait irq softirq steal guest guest_nice
    local total_before idle_before
    local total_after idle_after
    local total_delta idle_delta usage

    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice \
        < /proc/stat || {
            print -r -- "Unavailable"
            return 1
        }

    total_before=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
    idle_before=$(( idle + iowait ))

    sleep 0.25

    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice \
        < /proc/stat || {
            print -r -- "Unavailable"
            return 1
        }

    total_after=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
    idle_after=$(( idle + iowait ))

    total_delta=$(( total_after - total_before ))
    idle_delta=$(( idle_after - idle_before ))

    if (( total_delta <= 0 )); then
        print -r -- "0%"
        return
    fi

    usage=$(( 100 * (total_delta - idle_delta) / total_delta ))
    print -r -- "${usage}%"
}

monitor_memory_usage() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local total_kb
    local available_kb
    local used_kb
    local percentage

    total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    available_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"

    [[ "$total_kb" == <-> && "$available_kb" == <-> ]] || {
        print -r -- "Unavailable"
        return 1
    }

    used_kb=$(( total_kb - available_kb ))
    percentage=$(( used_kb * 100 / total_kb ))

    printf '%.1f / %.1f GiB (%d%%)\n' \
        "$(( used_kb / 1048576.0 ))" \
        "$(( total_kb / 1048576.0 ))" \
        "$percentage"
}

monitor_load_average() {
    emulate -L zsh

    if [[ -r /proc/loadavg ]]; then
        awk '{print $1", "$2", "$3}' /proc/loadavg
    else
        print -r -- "Unavailable"
    fi
}

monitor_uptime() {
    emulate -L zsh

    LC_ALL=C uptime -p 2>/dev/null ||
        print -r -- "Unavailable"
}

monitor_root_usage() {
    emulate -L zsh
    (( $+commands[python3] )) || { print -r -- "Unavailable (Python 3 required)"; return 1; }
    python3 -B "$ARCHMIND_ROOT/tools/storage-info.py" --summary
}

monitor_failed_services_count() {
    emulate -L zsh

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --failed --no-legend 2>/dev/null |
            sed '/^[[:space:]]*$/d' |
            wc -l |
            tr -d ' '
    else
        print -r -- "0"
    fi
}

monitor_collect_overview() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga MONITOR_OVERVIEW_LINES

    local cpu_model
    local cpu_usage
    local memory
    local load
    local uptime_value
    local root_usage
    local failed_services

    cpu_model="$(monitor_cpu_model)"
    cpu_usage="$(monitor_cpu_usage)"
    memory="$(monitor_memory_usage)"
    load="$(monitor_load_average)"
    uptime_value="$(monitor_uptime)"
    root_usage="$(monitor_root_usage)"
    failed_services="$(monitor_failed_services_count)"

    MONITOR_OVERVIEW_LINES=(
        "CPU ................ ${cpu_model}"
        "CPU usage ......... ${cpu_usage}"
        "Memory ............ ${memory}"
        "Load 1/5/15 min ... ${load}"
        "Storage / .... ${root_usage}"
        "Uptime ....... ${uptime_value}"
        "Failed services .... ${failed_services}"
    )
}

monitor_collect_processes() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga MONITOR_PROCESS_LINES

    local process_output

    process_output="$(
        ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null |
            head -n 12 |
            awk '
                NR == 1 {
                    printf "%-8s %-25s %-8s %-8s\n", $1, $2, $3, $4
                    next
                }

                {
                    printf "%-8s %-25s %-8s %-8s\n", $1, $2, $3, $4
                }
            '
    )"

    MONITOR_PROCESS_LINES=(
        "Processes with highest CPU use (lifetime average):"
        ""
        "$process_output"
    )
}

monitor_collect_temperatures() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga MONITOR_TEMPERATURE_LINES

    local sensor_output=""

    if command -v sensors >/dev/null 2>&1; then
        sensor_output="$(
            sensors 2>/dev/null |
                grep -E 'Package id|Tctl|Tdie|Core [0-9]+|edge|junction|Composite' |
                head -n 14
        )"
    fi

    if [[ -z "$sensor_output" ]]; then
        MONITOR_TEMPERATURE_LINES=(
            "No readable sensors were found."
            ""
            "On Arch Linux, the command is provided by:"
            "lm_sensors"
        )
    else
        MONITOR_TEMPERATURE_LINES=(
            "Detected temperatures:"
            ""
            "$sensor_output"
        )
    fi
}

monitor_collect_failed_services() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga MONITOR_SERVICE_LINES

    local failed_output=""

    if command -v systemctl >/dev/null 2>&1; then
        failed_output="$(
            systemctl --failed --no-legend --no-pager 2>/dev/null |
                head -n 12
        )"
    fi

    if [[ -z "$failed_output" ]]; then
        MONITOR_SERVICE_LINES=(
            "No failed services were found."
        )
    else
        MONITOR_SERVICE_LINES=(
            "Failed services:"
            ""
            "$failed_output"
        )
    fi
}
