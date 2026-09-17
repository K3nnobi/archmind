#!/usr/bin/env bash

extract_archmind_backup() {
  local source="$1"
  local target
  target="$(mktemp -d "${ARCHMIND_TEMP_DIR}/restore.XXXXXX")"
  tar -xaf "$source" -C "$target"
  printf '%s\n' "$target"
}

restore_configs_module() {
  local source="$1"
  [[ -d "${source}/configs" ]] || {
    ui_warn "Backup does not contain settings."
    return 0
  }

  local item name destination
  while IFS= read -r -d '' item; do
    name="$(basename "$item")"

    if [[ "$name" == "archmind-doctor-reports" ]]; then
      if [[ -f "$ARCHMIND_CORE_DIR/tools/doctor-report.py" ]] && has python3; then
        python3 -B "$ARCHMIND_CORE_DIR/tools/doctor-report.py" --import "$item" || \
          ui_warn "Doctor report restore was incomplete; existing reports were preserved."
      else
        ui_warn "Doctor reports were not restored: the report helper or Python is missing."
      fi
      continue
    fi

    if [[ "$name" == "archmind-config" && -d "$item" ]]; then
      mkdir -p "$ARCHMIND_CONFIG_DIR"
      cp -a -- "$item/." "$ARCHMIND_CONFIG_DIR/"
      continue
    fi

    if [[ "$name" == ".zsh_aliases" ]]; then
      mkdir -p "$ARCHMIND_ZSH_DIR"
      cp -a -- "$item" "$ARCHMIND_ALIASES_FILE"
      continue
    fi

    if [[ "$name" == ".p10k.zsh" ]]; then
      mkdir -p "$ARCHMIND_ZSH_DIR"
      cp -a -- "$item" "$ARCHMIND_P10K_FILE"
      continue
    fi

    if [[ "$name" == ".config" ]]; then
      mkdir -p "${HOME}/.config"
      local config_item config_name
      while IFS= read -r -d '' config_item; do
        config_name="$(basename "$config_item")"
        [[ "$config_name" == "archmind" ]] && continue
        destination="${HOME}/.config/${config_name}"
        [[ ! -e "$destination" || -w "$destination" ]] || {
          ui_error "Permission denied while restoring: $destination"
          return 1
        }
        if [[ -d "$config_item" && ! -L "$config_item" ]]; then
          mkdir -p "$destination"
          cp -a -- "$config_item/." "$destination/"
        else
          cp -a -- "$config_item" "$destination"
        fi
      done < <(find "$item" -mindepth 1 -maxdepth 1 -print0)
      continue
    fi

    if [[ "$name" == ".local" && -d "$item" ]]; then
      local local_item local_name nested nested_name
      mkdir -p "${HOME}/.local"
      while IFS= read -r -d '' local_item; do
        local_name="$(basename "$local_item")"
        if [[ "$local_name" == "bin" && -d "$local_item" ]]; then
          mkdir -p "${HOME}/.local/bin"
          while IFS= read -r -d '' nested; do
            nested_name="$(basename "$nested")"
            [[ "$nested_name" == "archmind" || "$nested_name" == "archmind-console" || "$nested_name" == "archmind-monitor" ]] && continue
            cp -a -- "$nested" "${HOME}/.local/bin/${nested_name}"
          done < <(find "$local_item" -mindepth 1 -maxdepth 1 -print0)
        elif [[ "$local_name" == "share" && -d "$local_item" ]]; then
          mkdir -p "${HOME}/.local/share"
          while IFS= read -r -d '' nested; do
            nested_name="$(basename "$nested")"
            [[ "$nested_name" == "archmind-toolkit" ]] && continue
            if [[ -d "$nested" && ! -L "$nested" ]]; then
              mkdir -p "${HOME}/.local/share/${nested_name}"
              cp -a -- "$nested/." "${HOME}/.local/share/${nested_name}/"
            else
              cp -a -- "$nested" "${HOME}/.local/share/${nested_name}"
            fi
          done < <(find "$local_item" -mindepth 1 -maxdepth 1 -print0)
        fi
      done < <(find "$item" -mindepth 1 -maxdepth 1 -print0)
      continue
    fi

    destination="${HOME}/${name}"
    [[ ! -e "$destination" || -w "$destination" ]] || {
      ui_error "Permission denied while restoring: $destination"
      return 1
    }
    if [[ -d "$item" && ! -L "$item" ]]; then
      mkdir -p "$destination"
      cp -a -- "$item/." "$destination/"
    else
      cp -a -- "$item" "$destination"
    fi
  done < <(find "${source}/configs" -mindepth 1 -maxdepth 1 -print0)

  local legacy canonical
  for legacy in .zsh_aliases .p10k.zsh; do
    case "$legacy" in
      .zsh_aliases) canonical="$ARCHMIND_ALIASES_FILE" ;;
      .p10k.zsh) canonical="$ARCHMIND_P10K_FILE" ;;
    esac
    if [[ -f "$canonical" && ! -e "$HOME/$legacy" && ! -L "$HOME/$legacy" ]]; then
      ln -s -- "$canonical" "$HOME/$legacy" || return 1
    fi
  done

  if [[ -f "$ARCHMIND_ALIASES_FILE" && -w "${HOME}/.zshrc" ]] && \
     ! grep -qF '$HOME/ArchMind/Config/Zsh/aliases.zsh' "${HOME}/.zshrc"; then
    printf '\n%s\n' '[[ -r "$HOME/ArchMind/Config/Zsh/aliases.zsh" ]] && source "$HOME/ArchMind/Config/Zsh/aliases.zsh"' >> "${HOME}/.zshrc"
  fi
  ui_ok "Settings restored."
}

restore_gnome_module() {
  local source="$1"
  [[ -d "${source}/gnome" ]] || {
    ui_warn "Backup does not contain GNOME data."
    return 0
  }

  mkdir -p "${HOME}/.local/share/gnome-shell/extensions"
  [[ -d "${source}/gnome/extensions" ]] && \
    cp -a "${source}/gnome/extensions/." \
      "${HOME}/.local/share/gnome-shell/extensions/"

  if has dconf; then
    [[ -s "${source}/gnome/dconf/interface.dconf" ]] && \
      dconf load /org/gnome/desktop/interface/ \
        < "${source}/gnome/dconf/interface.dconf"

    [[ -s "${source}/gnome/dconf/background.dconf" ]] && \
      dconf load /org/gnome/desktop/background/ \
        < "${source}/gnome/dconf/background.dconf"

    [[ -s "${source}/gnome/dconf/gnome-shell.dconf" ]] && \
      dconf load /org/gnome/shell/ \
        < "${source}/gnome/dconf/gnome-shell.dconf"
  fi

  if has gnome-extensions && [[ -f "${source}/gnome/extensions-enabled.txt" ]]; then
    while IFS= read -r uuid; do
      [[ -n "$uuid" ]] && gnome-extensions enable "$uuid" 2>/dev/null || true
    done < "${source}/gnome/extensions-enabled.txt"
  fi

  ui_ok "GNOME and extensions restored."
}

restore_packages_module() {
  local source="$1"
  [[ -d "${source}/packages" ]] || {
    ui_warn "Backup does not contain packages."
    return 0
  }

  local work official available unavailable package
  local aur available_aur unavailable_aur
  work="$(mktemp -d "${ARCHMIND_TEMP_DIR}/packages.XXXXXX")"
  official="${work}/official.txt"
  available="${work}/official-available.txt"
  unavailable="${work}/official-unavailable.txt"
  aur="${work}/aur.txt"
  available_aur="${work}/aur-available.txt"
  unavailable_aur="${work}/aur-unavailable.txt"

  { sed '/^[[:space:]]*$/d' "${source}/packages/pacman-native.txt" 2>/dev/null || true
    printf '%s\n' zsh zsh-autosuggestions zsh-syntax-highlighting zsh-completions
  } | LC_ALL=C sort -u > "$official"

  { sed '/^[[:space:]]*$/d' "${source}/packages/pacman-aur.txt" 2>/dev/null || true
    printf '%s\n' zsh-theme-powerlevel10k-git
  } | LC_ALL=C sort -u > "$aur"

  if [[ -f "${source}/configs/.local/share/thumbnailers/exe-thumbnailer.thumbnailer" ]]; then
    printf '%s\n' python-pillow icoutils >> "$official"
    printf '%s\n' icoextract >> "$aur"
    LC_ALL=C sort -u -o "$official" "$official"
    LC_ALL=C sort -u -o "$aur" "$aur"
  fi

  if [[ -d "${source}/gnome" ]]; then
    printf '%s\n' papirus-icon-theme >> "$official"
    printf '%s\n' gnome-rounded-blur papirus-folders >> "$aur"
    LC_ALL=C sort -u -o "$official" "$official"
    LC_ALL=C sort -u -o "$aur" "$aur"
  fi

  if [[ -f "${source}/configs/archmind-config/Patches/Plymouth/state.conf" ]]; then
    printf '%s\n' plymouth >> "$official"
    LC_ALL=C sort -u -o "$official" "$official"
  fi

  sudo pacman -Syu --noconfirm || { rm -rf -- "$work"; return 1; }

  : > "$available"
  : > "$unavailable"
  while IFS= read -r package; do
    pacman -Si -- "$package" >/dev/null 2>&1 \
      && printf '%s\n' "$package" >> "$available" \
      || printf '%s\n' "$package" >> "$unavailable"
  done < "$official"

  if [[ -s "$available" ]]; then
    mapfile -t official_packages < "$available"
    sudo pacman -S --needed --noconfirm -- "${official_packages[@]}" || {
      ui_error "Failed to install official packages."
      rm -rf -- "$work"
      return 1
    }
  fi

  if [[ -s "$aur" ]]; then
    if ! has yay; then
      ui_warn "yay is missing; attempting to install it to restore AUR packages."
      install_yay || true
    fi

    if has yay; then
      : > "$available_aur"
      : > "$unavailable_aur"
      while IFS= read -r package; do
        yay -Si -- "$package" >/dev/null 2>&1 \
          && printf '%s\n' "$package" >> "$available_aur" \
          || printf '%s\n' "$package" >> "$unavailable_aur"
      done < "$aur"

      while IFS= read -r package; do
        yay -S --needed --noconfirm -- "$package" || \
          printf '%s\n' "$package" >> "${work}/aur-failed.txt"
      done < "$available_aur"
    else
      ui_warn "yay is missing; AUR packages remain pending."
    fi
  fi

  if [[ -s "$unavailable" || -s "$unavailable_aur" || -s "${work}/aur-failed.txt" ]]; then
    local report="${ARCHMIND_LOG_DIR}/package-restore-$(date +'%Y%m%d-%H%M%S')"
    mkdir -p "$report"
    cp -a -- "$work/." "$report/"
    ui_warn "Some packages remain pending; review the ArchMind logs."
  fi

  rm -rf -- "$work"
}

restore_backup() {
  local mode="$1"
  local backup
  backup="$(latest_archmind_backup)"

  [[ -n "$backup" ]] || {
    ui_error "No .archmind backup found."
    return 1
  }

  ui_info "Backup found: $backup"
  confirm "Continue?" || return 0

  local extracted
  extracted="$(extract_archmind_backup "$backup")"

  (
    cd "$extracted"
    sha256sum -c checksums.sha256 >/dev/null
  ) || {
    ui_error "Backup verification failed."
    return 1
  }

  case "$mode" in
    complete)
      restore_packages_module "$extracted"
      restore_configs_module "$extracted"
      restore_gnome_module "$extracted"
      configure_nautilus_profile
      configure_gnome_appearance_profile
      if [[ -f "$ARCHMIND_CONFIG_DIR/NVIDIA/vibrance.conf" ]]; then
        configure_nvibrant_profile
      fi
      ;;
    gnome)
      restore_gnome_module "$extracted"
      configure_nautilus_profile
      configure_gnome_appearance_profile
      ;;
    packages)
      restore_packages_module "$extracted"
      ;;
  esac

  rm -rf "$extracted"
  ui_warn "Restart the session after restoring GNOME or the shell."
}
