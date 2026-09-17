#!/usr/bin/env zsh

system_get_distribution() {
    emulate -L zsh

    if [[ -r /etc/os-release ]]; then
        local name
        name="$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2-)"
        name="${name#\"}"
        name="${name%\"}"
        print -r -- "${name:-Arch Linux}"
    else
        print -r -- "Unknown system"
    fi
}

system_get_kernel() {
    emulate -L zsh
    uname -r 2>/dev/null || print -r -- "Unavailable"
}

system_get_hostname() {
    emulate -L zsh
    hostname 2>/dev/null || print -r -- "${HOST:-Unavailable}"
}

system_get_uptime() {
    emulate -L zsh

    if command -v uptime >/dev/null 2>&1; then
        LC_ALL=C uptime -p 2>/dev/null
    else
        print -r -- "Unavailable"
    fi
}

system_get_memory() {
    emulate -L zsh

    if [[ -r /proc/meminfo ]]; then
        local total_kb available_kb used_kb

        total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
        available_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"

        [[ "$total_kb" == <-> ]] || {
            print -r -- "Unavailable"
            return
        }

        [[ "$available_kb" == <-> ]] || { print -r -- "Unavailable"; return 1; }
        used_kb=$(( total_kb - available_kb ))

        printf '%.1f GiB used / %.1f GiB\n' \
            "$(( used_kb / 1048576.0 ))" \
            "$(( total_kb / 1048576.0 ))"
    else
        print -r -- "Unavailable"
    fi
}

system_get_package_count() {
    emulate -L zsh

    if command -v pacman >/dev/null 2>&1; then
        pacman -Qq 2>/dev/null | wc -l | tr -d ' '
    else
        print -r -- "Unavailable"
    fi
}

system_collect_information() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga SYSTEM_INFORMATION_LINES

    local distribution
    local kernel
    local hostname_value
    local uptime_value
    local memory
    local packages
    local desktop
    local shell_name

    distribution="$(system_get_distribution)"
    kernel="$(system_get_kernel)"
    hostname_value="$(system_get_hostname)"
    uptime_value="$(system_get_uptime)"
    memory="$(system_get_memory)"
    packages="$(system_get_package_count)"

    desktop="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-Unavailable}}"
    shell_name="${SHELL:t}"

    SYSTEM_INFORMATION_LINES=(
        "Distribution ....... ${distribution}"
        "Kernel ............. ${kernel}"
        "Hostname ........... ${hostname_value}"
        "User ............ ${USER:-Unavailable}"
        "Shell .............. ${shell_name:-Zsh}"
        "Desktop ............ ${desktop}"
        "Session ............. ${XDG_SESSION_TYPE:-Unavailable}"
        "Uptime ....... ${uptime_value}"
        "Memory ............ ${memory}"
        "Pacman packages ..... ${packages}"
    )
}
