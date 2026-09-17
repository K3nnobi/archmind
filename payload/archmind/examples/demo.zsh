#!/usr/bin/env zsh

emulate -L zsh
setopt localoptions typesetsilent

typeset -g BASE="${${(%):-%N}:A:h:h}"

source "$BASE/core/afi/header.zsh"
source "$BASE/core/afi/panel.zsh"

clear

afi_header "v2.1 Responsive" "Arch Linux"

print

afi_panel \
    --title "AFI Status" \
    --width "55%" \
    --padding 2 \
    --blank-top \
    --blank-bottom \
    "Graphics engine loaded." \
    "Paleta azul ativa." \
    "Layout responsivo funcionando." \
    "Reusable panel available."

print

afi_panel \
    --title "Next step" \
    --width "auto" \
    --padding 2 \
    --blank-top \
    --blank-bottom \
    "Create the footer and navigable menu."

print
