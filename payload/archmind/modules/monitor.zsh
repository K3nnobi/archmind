# ==========================================
# ArchMind Monitor Module
# Intelligence meets Linux
# ==========================================

archmind_temperatures() {
    echo
    print -P "%F{cyan}%BTEMPERATURES%b%f"
    echo

    if command -v sensors >/dev/null 2>&1; then
        sensors
    else
        _archmind_warn "The sensors command is not installed."
        echo
        echo "Install with:"
        echo "  sudo pacman -S lm_sensors"
        return 1
    fi

    echo
}

archmind_gpu() {
    echo
    print -P "%F{cyan}%BGPU%b%f"
    echo

    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_data

        gpu_data="$(
            nvidia-smi \
                --query-gpu=name,driver_version,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw \
                --format=csv,noheader,nounits \
                2>/dev/null |
            head -n 1
        )"

        if [[ -n "$gpu_data" ]]; then
            local gpu_name
            local driver
            local temperature
            local utilization
            local memory_used
            local memory_total
            local power

            IFS=',' read -r \
                gpu_name \
                driver \
                temperature \
                utilization \
                memory_used \
                memory_total \
                power <<< "$gpu_data"

            gpu_name="${gpu_name## }"
            driver="${driver## }"
            temperature="${temperature## }"
            utilization="${utilization## }"
            memory_used="${memory_used## }"
            memory_total="${memory_total## }"
            power="${power## }"

            printf "%-15s %s\n" "Model:" "$gpu_name"
            printf "%-15s %s\n" "Driver:" "$driver"
            printf "%-15s %s °C\n" "Temperature:" "$temperature"
            printf "%-15s %s%%\n" "Utilization:" "$utilization"
            printf "%-15s %s / %s MiB\n" \
                "VRAM:" "$memory_used" "$memory_total"
            printf "%-15s %s W\n" "Power draw:" "$power"
        else
            _archmind_error "The NVIDIA GPU did not respond."
            return 1
        fi

    elif command -v lspci >/dev/null 2>&1; then
        local gpu_devices

        gpu_devices="$(
            lspci |
            grep -Ei 'vga|3d|display' |
            sed 's/^[^ ]* //'
        )"

        if [[ -n "$gpu_devices" ]]; then
            print -r -- "$gpu_devices"
            echo
            _archmind_warn "Advanced monitoring is unavailable for this GPU."
        else
            _archmind_warn "No GPU was identified."
            return 1
        fi
    else
        _archmind_error "Could not query the GPU."
        return 1
    fi

    echo
}

archmind_processes() {
    echo
    print -P "%F{cyan}%BHIGHEST CPU USAGE%b%f"
    echo

    printf "%-8s %-10s %-7s %-7s %s\n" \
        "PID" "USER" "CPU%" "MEM%" "COMMAND"

    ps -eo pid,user,%cpu,%mem,comm \
        --sort=-%cpu |
        head -n 11

    echo
}

archmind_memory_processes() {
    echo
    print -P "%F{cyan}%BHIGHEST MEMORY USAGE%b%f"
    echo

    printf "%-8s %-10s %-7s %-7s %s\n" \
        "PID" "USER" "CPU%" "MEM%" "COMMAND"

    ps -eo pid,user,%cpu,%mem,comm \
        --sort=-%mem |
        head -n 11

    echo
}

archmind_monitor() {
    if command -v btop >/dev/null 2>&1; then
        btop
    elif command -v htop >/dev/null 2>&1; then
        htop
    elif command -v top >/dev/null 2>&1; then
        top
    else
        _archmind_error "No system monitor was found."
        return 1
    fi
}

archmind_status() {
    echo
    print -P "%F{cyan}%BARCHMIND STATUS%b%f"
    print -P "%F{magenta}Quick machine overview%f"
    echo

    if command -v uptime >/dev/null 2>&1; then
        printf "%-16s %s\n" \
            "Uptime:" \
            "$(uptime -p 2>/dev/null)"
    fi

    if command -v free >/dev/null 2>&1; then
        local memory
        memory="$(free -h | awk '/^Mem:/ {print $3 " / " $2}')"
        printf "%-16s %s\n" "Memory:" "$memory"
    fi

    if command -v df >/dev/null 2>&1; then
        local disk
        disk="$(df -hP / | awk 'NR == 2 {print $3 " / " $2 " (" $5 ")"}')"
        printf "%-16s %s\n" "Root disk:" "$disk"
    fi

    if command -v sensors >/dev/null 2>&1; then
        local cpu_temp

        cpu_temp="$(
            sensors 2>/dev/null |
            awk '
                /Package id 0:/ {
                    print $4
                    exit
                }
                /Tctl:/ {
                    print $2
                    exit
                }
                /CPU Temperature:/ {
                    print $3
                    exit
                }
            '
        )"

        [[ -n "$cpu_temp" ]] &&
            printf "%-16s %s\n" "CPU:" "$cpu_temp"
    fi

    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_status

        gpu_status="$(
            nvidia-smi \
                --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total \
                --format=csv,noheader,nounits \
                2>/dev/null |
            head -n 1
        )"

        if [[ -n "$gpu_status" ]]; then
            local gpu_temp
            local gpu_use
            local gpu_mem_used
            local gpu_mem_total

            IFS=',' read -r \
                gpu_temp \
                gpu_use \
                gpu_mem_used \
                gpu_mem_total <<< "$gpu_status"

            printf "%-16s %s °C, %s%%, %s/%s MiB\n" \
                "GPU:" \
                "${gpu_temp## }" \
                "${gpu_use## }" \
                "${gpu_mem_used## }" \
                "${gpu_mem_total## }"
        fi
    fi

    echo
}

# Direct shortcuts

temps() {
    archmind_temperatures
}

gpu() {
    archmind_gpu
}

processes() {
    archmind_processes
}

memprocesses() {
    archmind_memory_processes
}

monitor() {
    archmind_monitor
}

statuspc() {
    archmind_status
}
