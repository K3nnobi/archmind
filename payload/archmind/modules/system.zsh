# ==========================================
# ArchMind System Module
# Intelligence meets Linux
# ==========================================

archmind_system() {
    local hostname_name="${HOST:-$(hostname)}"
    local kernel
    local uptime_text
    local desktop="${XDG_CURRENT_DESKTOP:-Unknown}"
    local session="${XDG_SESSION_TYPE:-Unknown}"
    local shell_name="${SHELL:t}"

    kernel="$(uname -r)"
    uptime_text="$(uptime -p 2>/dev/null)"

    echo
    print -P "%F{cyan}%BARCHMIND SYSTEM%b%f"
    print -P "%F{magenta}Machine summary%f"
    echo

    printf "%-14s %s\n" "Computer:" "$hostname_name"
    printf "%-14s %s\n" "System:" "$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')"
    printf "%-14s %s\n" "Kernel:" "$kernel"
    printf "%-14s %s\n" "Desktop:" "$desktop"
    printf "%-14s %s\n" "Session:" "$session"
    printf "%-14s %s\n" "Shell:" "$shell_name"
    printf "%-14s %s\n" "Uptime:" "${uptime_text:-unavailable}"

    if command -v lscpu >/dev/null 2>&1; then
        printf "%-14s %s\n" "Processor:" \
            "$(lscpu | awk -F: '/Model name/ {
                sub(/^[ \t]+/, "", $2)
                print $2
                exit
            }')"
    fi

    if command -v free >/dev/null 2>&1; then
        local memory_used
        local memory_total

        memory_used="$(free -h | awk '/^Mem:/ {print $3}')"
        memory_total="$(free -h | awk '/^Mem:/ {print $2}')"

        printf "%-14s %s\n" "Memory:" "$memory_used / $memory_total"
    fi

    if command -v df >/dev/null 2>&1; then
        local root_used
        local root_total
        local root_percent

        read -r root_total root_used root_percent <<< \
            "$(df -hP / | awk 'NR == 2 {print $2, $3, $5}')"

        printf "%-14s %s\n" "Root disk:" "$root_used / $root_total ($root_percent)"
    fi

    echo
}

archmind_memory() {
    echo
    print -P "%F{cyan}%BMEMORY%b%f"
    echo

    if command -v free >/dev/null 2>&1; then
        free -h
    else
        _archmind_error "The free command was not found."
        return 1
    fi

    echo
}

archmind_disk() {
    echo
    print -P "%F{cyan}%BSTORAGE%b%f"
    echo

    print -P "%BMounted partitions%b"
    df -hT \
        -x tmpfs \
        -x devtmpfs \
        -x squashfs \
        2>/dev/null

    if command -v lsblk >/dev/null 2>&1; then
        echo
        print -P "%BBlock devices%b"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,FSUSE%,MOUNTPOINTS
    fi

    echo
}

archmind_battery() {
    local battery_path
    battery_path=(/sys/class/power_supply/BAT*(N))

    if (( ${#battery_path[@]} == 0 )); then
        _archmind_warn "No battery was detected."
        return 1
    fi

    local battery="${battery_path[1]}"
    local capacity="?"
    local status="Unknown"
    local health="Unavailable"

    [[ -r "$battery/capacity" ]] && capacity="$(<"$battery/capacity")"
    [[ -r "$battery/status" ]] && status="$(<"$battery/status")"

    local full_design
    local full_current

    if [[ -r "$battery/energy_full_design" &&
          -r "$battery/energy_full" ]]; then

        full_design="$(<"$battery/energy_full_design")"
        full_current="$(<"$battery/energy_full")"

    elif [[ -r "$battery/charge_full_design" &&
            -r "$battery/charge_full" ]]; then

        full_design="$(<"$battery/charge_full_design")"
        full_current="$(<"$battery/charge_full")"
    fi

    if [[ -n "$full_design" &&
          -n "$full_current" &&
          "$full_design" -gt 0 ]] 2>/dev/null; then

        health="$(( full_current * 100 / full_design ))%"
    fi

    case "$status" in
        Charging)
            status="Charging"
            ;;
        Discharging)
            status="Discharging"
            ;;
        Full)
            status="Full"
            ;;
        "Not charging")
            status="Connected, not charging"
            ;;
    esac

    echo
    print -P "%F{cyan}%BBATTERY%b%f"
    echo
    printf "%-13s %s%%\n" "Charge:" "$capacity"
    printf "%-13s %s\n" "State:" "$status"
    printf "%-13s %s\n" "Health:" "$health"
    echo
}

archmind_updates() {
    echo
    print -P "%F{cyan}%BSYSTEM UPDATES%b%f"
    echo

    local official_updates=""
    local aur_updates=""
    local official_count=0
    local aur_count=0

    # Official repositories
    print -P "%BOfficial repositories%b"
    echo

    if command -v checkupdates >/dev/null 2>&1; then
        official_updates="$(checkupdates 2>/dev/null)"

        if [[ -n "$official_updates" ]]; then
            print -r -- "$official_updates"
            official_count="$(
                print -r -- "$official_updates" |
                sed '/^[[:space:]]*$/d' |
                wc -l
            )"
        else
            _archmind_ok "No official update available."
        fi
    else
        _archmind_warn "The checkupdates command is not installed."
        echo "Install with:"
        echo "  sudo pacman -S pacman-contrib"
    fi

    echo
    print -P "%BAUR%b"
    echo

    # AUR
    if [[ "$ARCHMIND_UPDATE_CHECK_AUR" == "true" ]]; then
        if command -v yay >/dev/null 2>&1; then
            aur_updates="$(yay -Qua 2>/dev/null)"

            if [[ -n "$aur_updates" ]]; then
                print -r -- "$aur_updates"
                aur_count="$(
                    print -r -- "$aur_updates" |
                    sed '/^[[:space:]]*$/d' |
                    wc -l
                )"
            else
                _archmind_ok "No AUR update available."
            fi
        else
            _archmind_warn "Yay is not installed."
        fi
    else
        _archmind_warn "AUR checks are disabled in settings."
    fi

    echo
    print -P "%F{cyan}%BSUMMARY%b%f"
    echo

    printf "%-22s %s\n" "Official:" "$official_count"
    printf "%-22s %s\n" "AUR:" "$aur_count"
    printf "%-22s %s\n" \
        "Total:" \
        "$((official_count + aur_count))"

    echo
}

# Direct shortcuts
sys() {
    archmind_system
}

memory() {
    archmind_memory
}

disk() {
    archmind_disk
}

battery() {
    archmind_battery
}

updates() {
    archmind_updates
}
