#!/usr/bin/env bash

doctor_check_command() {
  local label="$1"
  local command="$2"

  if has "$command"; then
    printf '\033[1;32m✔\033[0m %s\n' "$label"
  else
    printf '\033[1;31m✘\033[0m %s\n' "$label"
  fi
}

doctor_run() {
  ui_header "ArchMind Doctor"

  doctor_check_command "Pacman" pacman
  doctor_check_command "Yay" yay
  doctor_check_command "Pamac" pamac
  doctor_check_command "Zsh" zsh
  doctor_check_command "GNOME Terminal" gnome-terminal
  doctor_check_command "Fastfetch" fastfetch
  doctor_check_command "Steam" steam
  doctor_check_command "Wine" wine
  doctor_check_command "Winetricks" winetricks
  doctor_check_command "EasyEffects" easyeffects
  doctor_check_command "FFmpeg" ffmpeg
  doctor_check_command "GStreamer" gst-launch-1.0
  doctor_check_command "Git" git
  doctor_check_command "Docker" docker

  echo
  [[ -d "$USER_EXT_DIR" ]] \
    && printf '\033[1;32m✔\033[0m Local GNOME extensions\n' \
    || printf '\033[1;31m✘\033[0m Local GNOME extensions\n'

  [[ -f "${HOME}/.zshrc" ]] \
    && printf '\033[1;32m✔\033[0m Zsh configuration\n' \
    || printf '\033[1;31m✘\033[0m Zsh configuration\n'

}
