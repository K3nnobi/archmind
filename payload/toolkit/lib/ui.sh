#!/usr/bin/env bash

ui_header() {
  clear
  printf '\033[1;36m%s\033[0m\n' "══════════════════════════════════════════════"
  printf '\033[1;36m%s\033[0m\n' "              $1"
  printf '\033[1;36m%s\033[0m\n\n' "══════════════════════════════════════════════"
}

ui_info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ui_ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
ui_warn()  { printf '\033[1;33m[WARNING]\033[0m %s\n' "$*"; }
ui_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

ui_pause() {
  echo
  read -rp "Press Enter to continue..." _
}
