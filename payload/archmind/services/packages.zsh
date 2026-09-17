#!/usr/bin/env zsh

packages_has_command() {
    emulate -L zsh

    command -v "$1" >/dev/null 2>&1
}

packages_pacman_count() {
    emulate -L zsh

    if ! packages_has_command pacman; then
        print -r -- "0"
        return 1
    fi

    pacman -Qq 2>/dev/null |
        wc -l |
        tr -d ' '
}

packages_explicit_count() {
    emulate -L zsh

    if ! packages_has_command pacman; then
        print -r -- "0"
        return 1
    fi

    pacman -Qqe 2>/dev/null |
        wc -l |
        tr -d ' '
}

packages_foreign_count() {
    emulate -L zsh

    if ! packages_has_command pacman; then
        print -r -- "0"
        return 1
    fi

    pacman -Qqm 2>/dev/null |
        wc -l |
        tr -d ' '
}

packages_orphan_count() {
    emulate -L zsh

    if ! packages_has_command pacman; then
        print -r -- "0"
        return 1
    fi

    local count=0

    count="$(
        pacman -Qtdq 2>/dev/null |
            sed '/^[[:space:]]*$/d' |
            wc -l |
            tr -d ' '
    )"

    [[ "$count" == <-> ]] || count=0

    print -r -- "$count"
}

packages_flatpak_count() {
    emulate -L zsh

    if ! packages_has_command flatpak; then
        print -r -- "0"
        return 1
    fi

    flatpak list --app --columns=application 2>/dev/null |
        sed '/^[[:space:]]*$/d' |
        wc -l |
        tr -d ' '
}

packages_aur_helper() {
    emulate -L zsh

    local helper=""

    for helper in yay paru pikaur; do
        if packages_has_command "$helper"; then
            print -r -- "$helper"
            return 0
        fi
    done

    print -r -- "None"
    return 1
}

packages_collect_summary() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga PACKAGE_SUMMARY_LINES

    local pacman_state="Missing"
    local aur_helper="None"
    local flatpak_state="Missing"

    local total=0
    local explicit=0
    local foreign=0
    local orphan=0
    local flatpak_total=0

    if packages_has_command pacman; then
        pacman_state="Available"
        total="$(packages_pacman_count)"
        explicit="$(packages_explicit_count)"
        foreign="$(packages_foreign_count)"
        orphan="$(packages_orphan_count)"
    fi

    aur_helper="$(packages_aur_helper)" || true

    if packages_has_command flatpak; then
        flatpak_state="Available"
        flatpak_total="$(packages_flatpak_count)"
    fi

    PACKAGE_SUMMARY_LINES=(
        "Pacman .............. ${pacman_state}"
        "AUR helper ........ ${aur_helper}"
        "Flatpak ............. ${flatpak_state}"
        ""
        "Total packages ...... ${total}"
        "Explicit packages .. ${explicit}"
        "Foreign packages .... ${foreign}"
        "Orphan packages ...... ${orphan}"
        "Flatpak applications . ${flatpak_total}"
    )
}

packages_collect_updates() {
    emulate -L zsh
    typeset -ga PACKAGE_UPDATE_LINES
    local output
    if (( $+commands[python3] )); then
        output="$(ARCHMIND_DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}" python3 -B "$ARCHMIND_ROOT/tools/system-updates.py" 2>&1)" || true
    else
        output="Python 3 is required to check updates."
    fi
    PACKAGE_UPDATE_LINES=("$output")
}

packages_collect_orphans() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga PACKAGE_ORPHAN_LINES

    local orphan_output=""

    if ! packages_has_command pacman; then
        PACKAGE_ORPHAN_LINES=(
            "Pacman is unavailable."
        )
        return 1
    fi

    orphan_output="$(pacman -Qtdq 2>/dev/null || true)"

    if [[ -z "$orphan_output" ]]; then
        PACKAGE_ORPHAN_LINES=(
            "No orphan packages were found."
        )
        return 0
    fi

    PACKAGE_ORPHAN_LINES=(
        "Orphan packages found:"
        ""
        "$orphan_output"
        ""
        "No packages were removed."
    )
}

packages_collect_foreign() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga PACKAGE_FOREIGN_LINES

    local foreign_output=""

    if ! packages_has_command pacman; then
        PACKAGE_FOREIGN_LINES=(
            "Pacman is unavailable."
        )
        return 1
    fi

    foreign_output="$(
        pacman -Qm 2>/dev/null |
            head -n 24
    )"

    if [[ -z "$foreign_output" ]]; then
        PACKAGE_FOREIGN_LINES=(
            "No foreign packages were found."
        )
        return 0
    fi

    PACKAGE_FOREIGN_LINES=(
        "Foreign packages/AUR:"
        ""
        "$foreign_output"
        ""
        "List limited to the first entries."
    )
}

packages_collect_profiles() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga PACKAGE_PROFILE_LINES

    PACKAGE_PROFILE_LINES=(
        "Base Profile"
        "  Utilities, fonts, codecs and system integration."
        ""
        "Terminal Profile"
        "  Zsh, GNOME Terminal, plugins, Powerlevel10k and CLI tools."
        ""
        "Gaming Profile"
        "  Steam, Wine base, Lutris and related tools."
        "  Wine Compatibility Pack remains optional."
        ""
        "Audio Profile"
        "  PipeWire, EasyEffects and audio tools."
        ""
        "Development Profile"
        "  Python, Node.js, Docker and development tools."
        ""
        "Profile installation is handled by ArchMind Manager."
    )
}
