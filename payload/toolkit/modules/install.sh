#!/usr/bin/env bash

enable_multilib() {
  pacman -Sl multilib >/dev/null 2>&1 && return 0

  sudo cp -a /etc/pacman.conf \
    "/etc/pacman.conf.archmind.$(date +'%Y%m%d-%H%M%S').bak"

  sudo sed -i \
    '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ {
      s/^#\[multilib\]/[multilib]/
      s/^#Include = \/etc\/pacman.d\/mirrorlist/Include = \/etc\/pacman.d\/mirrorlist/
    }' /etc/pacman.conf

# Enabling a repository requires synchronizing and updating the whole system.
# Using only -Sy would leave Arch in a partially updated state.
  sudo pacman -Syu --noconfirm
}

install_available() {
  local packages=("$@")
  local available=()
  local pkg

  for pkg in "${packages[@]}"; do
    pacman -Si "$pkg" >/dev/null 2>&1 && available+=("$pkg")
  done

  [[ "${#available[@]}" -gt 0 ]] && \
    sudo pacman -S --needed --noconfirm "${available[@]}"
}

install_yay() {
  has yay && return 0

  sudo pacman -S --needed --noconfirm base-devel git
  local dir
  dir="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "${dir}/yay"

  (
    cd "${dir}/yay"
    makepkg -si --needed --noconfirm
  )

  rm -rf "$dir"
}

install_profile() {
  local profile="$1"
  require_arch || return 1

  local profile_file="${ARCHMIND_ROOT}/profiles/${profile}.conf"
  [[ -f "$profile_file" ]] || {
    ui_error "Profile not found: $profile"
    return 1
  }

  [[ "$profile" == "gaming" ]] && enable_multilib

  mapfile -t official < <(
    sed -n 's/^official=//p' "$profile_file" \
      | tr ' ' '\n' \
      | sed '/^$/d'
  )

  mapfile -t aur < <(
    sed -n 's/^aur=//p' "$profile_file" \
      | tr ' ' '\n' \
      | sed '/^$/d'
  )

  ui_info "Installing profile: $profile"

  [[ "${#official[@]}" -gt 0 ]] && install_available "${official[@]}"

  if [[ "${#aur[@]}" -gt 0 ]]; then
    install_yay
    yay -S --needed --noconfirm "${aur[@]}"
  fi

  case "$profile" in
    base)
      configure_file_templates
      configure_nautilus_profile
      configure_gnome_appearance_profile
      ;;
    terminal) configure_terminal_profile ;;
    gaming)
      configure_gamemode_blur_profile
      configure_nvibrant_profile
      ;;
  esac

  ui_ok "Profile installed: $profile"
}

configure_nautilus_profile() {
  local helper="${ARCHMIND_CORE_DIR}/tools/configure-nautilus.sh"

  if [[ ! -f "$helper" ]]; then
    ui_warn "Nautilus configurator not found: $helper"
    return 0
  fi

  bash "$helper" --apply || \
    ui_warn "The optional Nautilus integration failed; the profile will continue."
}

configure_gnome_appearance_profile() {
  local helper="${ARCHMIND_CORE_DIR}/tools/configure-gnome-appearance.sh"

  if [[ ! -f "$helper" ]]; then
    ui_warn "GNOME appearance configurator not found: $helper"
    return 0
  fi

  bash "$helper" --apply || \
    ui_warn "The optional GNOME appearance integration failed; the profile will continue."
}

configure_gamemode_blur_profile() {
  local helper="${ARCHMIND_CORE_DIR}/tools/configure-gamemode-blur.sh"

  if [[ ! -f "$helper" ]]; then
    ui_warn "GameMode + Blur configurator not found: $helper"
    return 0
  fi

  bash "$helper" --apply || \
    ui_warn "The optional GameMode + Blur integration failed; the profile will continue."
}

configure_nvibrant_profile() {
  local helper="${ARCHMIND_CORE_DIR}/tools/configure-nvibrant.sh"

  if [[ ! -f "$helper" ]]; then
    ui_warn "NVIDIA Vibrance configurator not found: $helper"
    return 0
  fi

  bash "$helper" --apply || \
    ui_warn "NVIDIA Vibrance was not applied; Gaming Profile will continue."
}

configure_file_templates() {
  local templates_dir=""
  local template

  if has xdg-user-dirs-update; then
    xdg-user-dirs-update >/dev/null 2>&1 || true
  fi

  if has xdg-user-dir; then
    templates_dir="$(xdg-user-dir TEMPLATES 2>/dev/null || true)"
  fi

  # When TEMPLATES is not configured, xdg-user-dir may return Home.
  # Never create loose templates directly in this directory.
  if [[ -z "$templates_dir" || "$templates_dir" == "$HOME" || \
        "$templates_dir" == "$HOME/" ]]; then
    templates_dir="$HOME/Templates"
    if has xdg-user-dirs-update; then
      xdg-user-dirs-update --set TEMPLATES "$templates_dir" \
        >/dev/null 2>&1 || true
    fi
  fi

  mkdir -p -- "$templates_dir"

  for template in \
    "Documento vazio.txt" \
    "Script Python.py" \
    "Script Shell.sh" \
    "Documento Markdown.md"; do
    [[ -e "$templates_dir/$template" || -L "$templates_dir/$template" ]] || \
      : > "$templates_dir/$template"
  done

  ui_ok "New Document menu templates configured at: $templates_dir"
}

configure_terminal_profile() {
  if has zsh; then
  if confirm "Make Zsh your default shell?"; then
      chsh -s "$(command -v zsh)"
    fi
  fi

  if [[ ! -f "${HOME}/.zshrc" ]]; then
    cat > "${HOME}/.zshrc" <<'EOF'
export PATH="$HOME/.local/bin:$PATH"

[[ -f /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]] && \
  source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme

[[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

autoload -Uz compinit
compinit

eval "$(zoxide init zsh 2>/dev/null)"
[[ -f "$HOME/ArchMind/Config/Zsh/p10k.zsh" ]] && source "$HOME/ArchMind/Config/Zsh/p10k.zsh"
[[ -r "$HOME/ArchMind/Config/Zsh/aliases.zsh" ]] && source "$HOME/ArchMind/Config/Zsh/aliases.zsh"

[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF
  fi

  if [[ -w "${HOME}/.zshrc" ]]; then
    grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "${HOME}/.zshrc" || \
      printf '\n%s\n' 'export PATH="$HOME/.local/bin:$PATH"' >> "${HOME}/.zshrc"
    grep -qF '$HOME/ArchMind/Config/Zsh/aliases.zsh' "${HOME}/.zshrc" || \
      printf '\n%s\n' '[[ -r "$HOME/ArchMind/Config/Zsh/aliases.zsh" ]] && source "$HOME/ArchMind/Config/Zsh/aliases.zsh"' >> "${HOME}/.zshrc"
    grep -qF '/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' "${HOME}/.zshrc" || \
      printf '\n%s\n' '[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' >> "${HOME}/.zshrc"
    grep -qF 'autoload -Uz compinit' "${HOME}/.zshrc" || \
      printf '\n%s\n%s\n' 'autoload -Uz compinit' 'compinit' >> "${HOME}/.zshrc"
    grep -qF '/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' "${HOME}/.zshrc" || \
      printf '\n%s\n' '[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' >> "${HOME}/.zshrc"
  else
      ui_warn "Permission denied while configuring: ${HOME}/.zshrc"
  fi
}

install_saved_profile() {
  [[ -f "$ARCHMIND_PROFILE_FILE" ]] || {
    ui_error "Saved profile not found."
    return 1
  }

  while IFS='=' read -r name enabled; do
    [[ "$enabled" == "true" ]] && install_profile "$name"
  done < "$ARCHMIND_PROFILE_FILE"
}
