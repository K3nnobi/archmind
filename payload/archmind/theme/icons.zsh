# ==========================================
# ArchMind Icons
# Requires a Nerd Font for complete rendering
# ==========================================

typeset -g ARCHMIND_ICON_ARCH="󰣇"
typeset -g ARCHMIND_ICON_AI="󰚩"
typeset -g ARCHMIND_ICON_CPU=""
typeset -g ARCHMIND_ICON_MEMORY=""
typeset -g ARCHMIND_ICON_DISK="󰋊"
typeset -g ARCHMIND_ICON_GPU="󰢮"
typeset -g ARCHMIND_ICON_TEMP=""
typeset -g ARCHMIND_ICON_NETWORK="󰖩"
typeset -g ARCHMIND_ICON_GIT=""
typeset -g ARCHMIND_ICON_BRANCH=""
typeset -g ARCHMIND_ICON_PYTHON=""
typeset -g ARCHMIND_ICON_FOLDER=""
typeset -g ARCHMIND_ICON_TERMINAL=""
typeset -g ARCHMIND_ICON_SETTINGS=""
typeset -g ARCHMIND_ICON_PACKAGE="󰏖"
typeset -g ARCHMIND_ICON_BATTERY=""
typeset -g ARCHMIND_ICON_SUCCESS=""
typeset -g ARCHMIND_ICON_WARNING=""
typeset -g ARCHMIND_ICON_ERROR=""
typeset -g ARCHMIND_ICON_ARROW="❯"

_archmind_icons_test() {
    echo
    _archmind_title "ARCHMIND ICON TEST"
    echo

    printf "%-18s %s\n" "Arch:" "$ARCHMIND_ICON_ARCH"
    printf "%-18s %s\n" "AI:" "$ARCHMIND_ICON_AI"
    printf "%-18s %s\n" "CPU:" "$ARCHMIND_ICON_CPU"
    printf "%-18s %s\n" "Memory:" "$ARCHMIND_ICON_MEMORY"
    printf "%-18s %s\n" "Disk:" "$ARCHMIND_ICON_DISK"
    printf "%-18s %s\n" "GPU:" "$ARCHMIND_ICON_GPU"
    printf "%-18s %s\n" "Temperature:" "$ARCHMIND_ICON_TEMP"
    printf "%-18s %s\n" "Network:" "$ARCHMIND_ICON_NETWORK"
    printf "%-18s %s\n" "Git:" "$ARCHMIND_ICON_GIT"
    printf "%-18s %s\n" "Python:" "$ARCHMIND_ICON_PYTHON"
    printf "%-18s %s\n" "Terminal:" "$ARCHMIND_ICON_TERMINAL"

    echo
}
