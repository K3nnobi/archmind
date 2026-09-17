#!/usr/bin/env zsh
# Quick read-only ArchMind Doctor pass after a successful package transaction.

emulate -L zsh
setopt localoptions typesetsilent

typeset -g ARCHMIND_ROOT="${${(%):-%N}:A:h:h}"
typeset -g ARCHMIND_DATA_HOME="${ARCHMIND_DATA_HOME:-$HOME/ArchMind}"

[[ -r "$ARCHMIND_ROOT/services/doctor.zsh" ]] || {
    print -u2 -- "ArchMind Doctor service is unavailable."
    exit 1
}

source "$ARCHMIND_ROOT/services/doctor.zsh"
doctor_collect_quick
doctor_record_report PostUpdate "${DOCTOR_QUICK_LINES[@]}" || true

print -r -- "ArchMind Doctor / Post-update"
print
print -rl -- "${DOCTOR_QUICK_LINES[@]}"
print
print -r -- "${DOCTOR_REPORT_NOTE:-Report was not saved.}"

(( DOCTOR_WARNINGS == 0 ))
