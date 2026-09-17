#!/usr/bin/env bash

settings_menu() {
  while true; do
    ui_header "Persistent profiles"

    cat "$ARCHMIND_PROFILE_FILE"
    echo
    echo "1) Alternar Base"
    echo "2) Alternar Terminal"
    echo "3) Alternar Gamer"
    echo "4) Alternar Desenvolvimento"
    echo "5) Toggle Audio"
    echo "0) Back"
    echo

    read -rp "Choice: " choice

    case "$choice" in
      1) toggle_profile base ;;
      2) toggle_profile terminal ;;
      3) toggle_profile gaming ;;
      4) toggle_profile development ;;
      5) toggle_profile audio ;;
      0) return 0 ;;
      *) ui_warn "Invalid option." ;;
    esac
  done
}

toggle_profile() {
  local name="$1"
  local current

  current="$(grep "^${name}=" "$ARCHMIND_PROFILE_FILE" | cut -d= -f2)"

  if [[ "$current" == "true" ]]; then
    sed -i "s/^${name}=true/${name}=false/" "$ARCHMIND_PROFILE_FILE"
  else
    sed -i "s/^${name}=false/${name}=true/" "$ARCHMIND_PROFILE_FILE"
  fi
}
