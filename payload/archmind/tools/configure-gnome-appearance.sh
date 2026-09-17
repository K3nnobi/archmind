#!/usr/bin/env bash
set -u

readonly ROUNDED_BLUR_KEY='/org/gnome/shell/extensions/blur-my-shell/rounded-blur-found'

gnome_info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
gnome_ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
gnome_warn()  { printf '\033[1;33m[WARNING]\033[0m %s\n' "$*"; }
gnome_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

gnome_has() {
  command -v "$1" >/dev/null 2>&1
}

gnome_is_available() {
  gnome_has gnome-shell && return 0
  [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] && return 0
  [[ "${XDG_SESSION_DESKTOP:-}" == *gnome* ]]
}

gnome_safe_remove_temp() {
  local path="${1:-}"

  case "$path" in
    /tmp/archmind-gnome.*|"${HOME}/ArchMind/Temp/"archmind-gnome.*)
      [[ -e "$path" ]] && rm -rf -- "$path"
      ;;
    "") ;;
    *) gnome_warn "Cleanup refused for unexpected temporary path: $path" ;;
  esac
}

gnome_install_yay() {
  gnome_has yay && return 0

  gnome_has pacman || {
    gnome_warn "Pacman not found; yay could not be prepared."
    return 1
  }
  gnome_has sudo || {
    gnome_warn "sudo not found; yay could not be prepared."
    return 1
  }

  if ! gnome_has git || ! pacman -Qq base-devel >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm base-devel git || {
      gnome_warn "Failed to install yay dependencies."
      return 1
    }
  fi

  local temp_dir=""
  mkdir -p -- "${HOME}/ArchMind/Temp" 2>/dev/null || true
  temp_dir="$(mktemp -d "${HOME}/ArchMind/Temp/archmind-gnome.XXXXXX" 2>/dev/null || \
    mktemp -d /tmp/archmind-gnome.XXXXXX)" || {
      gnome_warn "Could not create the temporary yay directory."
      return 1
    }

  if ! git clone --depth 1 https://aur.archlinux.org/yay.git "${temp_dir}/yay"; then
    gnome_safe_remove_temp "$temp_dir"
    gnome_warn "Failed to obtain yay from the AUR."
    return 1
  fi

  if ! (
    cd -- "${temp_dir}/yay"
    makepkg -si --needed --noconfirm
  ); then
    gnome_safe_remove_temp "$temp_dir"
    gnome_warn "Failed to build or install yay."
    return 1
  fi

  gnome_safe_remove_temp "$temp_dir"
  gnome_has yay
}

gnome_install_dependencies() {
  local failed=0

  if ! gnome_has pacman || ! gnome_has sudo; then
    gnome_warn "Pacman or sudo is unavailable; GNOME appearance support was not installed."
    return 1
  fi

  gnome_info "Ensuring the Papirus theme is installed..."
  sudo pacman -S --needed --noconfirm papirus-icon-theme || {
    gnome_warn "Failed to install papirus-icon-theme."
    failed=1
  }

  if ! gnome_install_yay; then
    gnome_warn "yay is unavailable; gnome-rounded-blur and papirus-folders remain pending."
    failed=1
  else
    gnome_info "Ensuring rounded blur and the Papirus folder configurator..."
    yay -S --needed --noconfirm -- gnome-rounded-blur || {
      gnome_warn "Failed to install gnome-rounded-blur from the AUR."
      failed=1
    }
    yay -S --needed --noconfirm -- papirus-folders || {
      gnome_warn "Failed to install papirus-folders from the AUR."
      failed=1
    }
  fi

  (( failed == 0 ))
}

gnome_apply_papirus_yellow() {
  if ! gnome_has papirus-folders; then
    gnome_warn "papirus-folders is unavailable; the yellow color was not applied."
    return 1
  fi

  if ! papirus-folders -C yellow --theme Papirus-Dark; then
    gnome_warn "Could not set Papirus-Dark folders to yellow."
    return 1
  fi

  gnome_ok "Papirus-Dark folders configured in yellow."
}

gnome_check_rounded_blur() {
  local detected=""

  if ! gnome_has dconf; then
    gnome_warn "dconf not found; Blur My Shell could not be checked."
    return 1
  fi

  detected="$(dconf read "$ROUNDED_BLUR_KEY" 2>/dev/null || true)"
  if [[ "$detected" == "true" ]]; then
    gnome_ok "Blur My Shell detectou o suporte a cantos arredondados."
    return 0
  fi

  gnome_warn "Blur My Shell has not detected rounded blur yet (state: ${detected:-undefined})."
  gnome_warn "Log out of GNOME and back in, then repeat the check."
  gnome_warn "After updating GNOME Shell/Mutter, rebuild with: yay -S --rebuild gnome-rounded-blur"
  return 1
}

configure_gnome_appearance() {
  local failed=0

  if (( EUID == 0 )); then
    gnome_error "Run as your normal user, without sudo."
    return 1
  fi

  if ! gnome_is_available; then
    gnome_warn "GNOME Shell was not detected; appearance integration skipped without interrupting ArchMind."
    return 0
  fi

  gnome_info "Configuring rounded blur and yellow Papirus-Dark folders..."
  gnome_install_dependencies || failed=1

  if ! pacman -Qq gnome-rounded-blur >/dev/null 2>&1; then
    gnome_warn "gnome-rounded-blur was not installed."
    failed=1
  fi

  gnome_apply_papirus_yellow || failed=1
  gnome_check_rounded_blur || failed=1

  gnome_warn "Logout/login may be required for GNOME Shell to load rounded blur."

  if (( failed )); then
    gnome_warn "Appearance integration completed partially; the rest of ArchMind will continue normally."
  else
    gnome_ok "GNOME appearance integration complete."
  fi

  # Optional feature: failures must never interrupt profiles or restorations.
  return 0
}

case "${1:-}" in
  ""|--apply) configure_gnome_appearance ;;
  --check) gnome_check_rounded_blur ;;
  --help|-h)
    printf '%s\n' \
      'Usage: configure-gnome-appearance.sh [--apply|--check]' \
      'Install rounded blur, check Blur My Shell, and set Papirus-Dark folders to yellow.'
    ;;
  *)
    gnome_error "Unknown option: $1"
    exit 2
    ;;
esac
