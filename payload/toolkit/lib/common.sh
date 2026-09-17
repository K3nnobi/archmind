#!/usr/bin/env bash

ARCHMIND_HOME="${HOME}/ArchMind"
ARCHMIND_SYSTEM_DIR="${ARCHMIND_HOME}/System"
ARCHMIND_CORE_DIR="${ARCHMIND_SYSTEM_DIR}/Core"
ARCHMIND_TOOLKIT_DIR="${ARCHMIND_SYSTEM_DIR}/Toolkit"
ARCHMIND_BACKUP_DIR="${ARCHMIND_HOME}/Backups"
ARCHMIND_PROJECT_DIR="${ARCHMIND_HOME}/Projects"
ARCHMIND_LOG_DIR="${ARCHMIND_HOME}/Logs"
ARCHMIND_TEMP_DIR="${ARCHMIND_HOME}/Temp"
ARCHMIND_CONFIG_DIR="${ARCHMIND_HOME}/Config"
ARCHMIND_PROFILE_FILE="${ARCHMIND_CONFIG_DIR}/profile.conf"
ARCHMIND_ZSH_DIR="${ARCHMIND_CONFIG_DIR}/Zsh"
ARCHMIND_ALIASES_FILE="${ARCHMIND_ZSH_DIR}/aliases.zsh"
ARCHMIND_P10K_FILE="${ARCHMIND_ZSH_DIR}/p10k.zsh"

has() {
  command -v "$1" >/dev/null 2>&1
}

archmind_init() {
  [[ "$EUID" -ne 0 ]] || {
        echo "Do not run ArchMind as root."
    exit 1
  }

  mkdir -p \
    "$ARCHMIND_BACKUP_DIR" \
    "$ARCHMIND_PROJECT_DIR" \
    "$ARCHMIND_LOG_DIR" \
    "$ARCHMIND_TEMP_DIR" \
    "$ARCHMIND_CONFIG_DIR" \
    "$ARCHMIND_ZSH_DIR"

  if [[ ! -f "$ARCHMIND_PROFILE_FILE" ]]; then
    cat > "$ARCHMIND_PROFILE_FILE" <<'EOF'
base=true
terminal=true
gaming=false
development=false
audio=true
EOF
  fi
}

require_arch() {
  [[ -f /etc/arch-release ]] || {
        ui_error "This module requires Arch Linux or a derivative."
    return 1
  }
}

latest_archmind_backup() {
  find "$ARCHMIND_BACKUP_DIR" -maxdepth 1 -type f -name '*.archmind' \
    -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -n1 \
    | cut -d' ' -f2-
}

confirm() {
  local answer
  read -rp "$1 [y/N]: " answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}
