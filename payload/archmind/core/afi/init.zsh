#!/usr/bin/env zsh

emulate -L zsh
setopt localoptions typesetsilent

typeset -g AFI_ROOT="${${(%):-%N}:A:h}"
typeset -g ARCHMIND_ROOT="${AFI_ROOT:h:h}"

typeset -ga AFI_REQUIRED_FILES

AFI_REQUIRED_FILES=(
    palette.zsh
    layout.zsh
    draw.zsh
    workspace.zsh
    input.zsh
    header.zsh
    panel.zsh
    menu.zsh
    footer.zsh
    context.zsh
    status.zsh
    breadcrumb.zsh
    dialog.zsh
    notification.zsh
    viewer.zsh
    external.zsh
    screens.zsh
    actions.zsh
)

afi_init() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local component=""
    local component_path=""

    for component in "${AFI_REQUIRED_FILES[@]}"; do
        component_path="$AFI_ROOT/$component"

        if [[ ! -r "$component_path" ]]; then
            print -u2 -- "ArchMind AFI: missing component:"
            print -u2 -- "$component_path"
            return 1
        fi

        source "$component_path" || {
            print -u2 -- "ArchMind AFI: failed to load:"
            print -u2 -- "$component_path"
            return 1
        }
    done

    return 0
}
