#!/usr/bin/env bash
set -u

readonly ARCHMIND_NAUTILUS_MARKER='/* ArchMind: Nautilus transparent thumbnails */'
readonly ARCHMIND_NAUTILUS_END='/* End ArchMind: Nautilus transparent thumbnails */'
readonly ARCHMIND_NAUTILUS_MIME_TYPES='application/x-ms-dos-executable;application/x-msdownload;application/vnd.microsoft.portable-executable;application/x-dosexec;application/x-wine-extension-exe;'

nautilus_info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
nautilus_ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
nautilus_warn()  { printf '\033[1;33m[WARNING]\033[0m %s\n' "$*"; }
nautilus_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

nautilus_has() {
  command -v "$1" >/dev/null 2>&1
}

nautilus_safe_remove_temp() {
  local path="${1:-}"

  case "$path" in
    /tmp/archmind-nautilus.*|"${HOME}/ArchMind/Temp/"archmind-nautilus.*)
      [[ -e "$path" ]] && rm -rf -- "$path"
      ;;
    "") ;;
    *) nautilus_warn "Cleanup refused for unexpected temporary path: $path" ;;
  esac
}

nautilus_install_yay() {
  nautilus_has yay && return 0

  nautilus_has pacman || {
    nautilus_warn "Pacman not found; yay could not be prepared."
    return 1
  }
  nautilus_has sudo || {
    nautilus_warn "sudo not found; yay could not be prepared."
    return 1
  }

  if ! nautilus_has git || ! pacman -Qq base-devel >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm base-devel git || {
      nautilus_warn "Failed to install yay dependencies."
      return 1
    }
  fi

  local temp_dir=""
  mkdir -p -- "${HOME}/ArchMind/Temp" 2>/dev/null || true
  temp_dir="$(mktemp -d "${HOME}/ArchMind/Temp/archmind-nautilus.XXXXXX" 2>/dev/null || \
    mktemp -d /tmp/archmind-nautilus.XXXXXX)" || {
      nautilus_warn "Could not create the temporary yay directory."
      return 1
    }

  if ! git clone --depth 1 https://aur.archlinux.org/yay.git "${temp_dir}/yay"; then
    nautilus_safe_remove_temp "$temp_dir"
    nautilus_warn "Failed to obtain yay from the AUR."
    return 1
  fi

  if ! (
    cd -- "${temp_dir}/yay"
    makepkg -si --needed --noconfirm
  ); then
    nautilus_safe_remove_temp "$temp_dir"
    nautilus_warn "Failed to build or install yay."
    return 1
  fi

  nautilus_safe_remove_temp "$temp_dir"
  nautilus_has yay
}

nautilus_install_dependencies() {
  local failed=0

  if ! nautilus_has pacman || ! nautilus_has sudo; then
    nautilus_warn "Pacman or sudo is unavailable; Nautilus dependencies were not installed."
    return 1
  fi

  nautilus_info "Ensuring python-pillow and icoutils are installed..."
  sudo pacman -S --needed --noconfirm python-pillow icoutils || {
    nautilus_warn "Failed to install python-pillow or icoutils."
    failed=1
  }

  if ! nautilus_install_yay; then
    nautilus_warn "yay is unavailable; icoextract remains pending."
    failed=1
  elif ! yay -S --needed --noconfirm icoextract; then
    nautilus_warn "Failed to install icoextract from the AUR."
    failed=1
  fi

  (( failed == 0 ))
}

nautilus_write_thumbnailer() {
  local directory="${HOME}/.local/share/thumbnailers"
  local target="${directory}/exe-thumbnailer.thumbnailer"
  local temporary=""

  if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
    nautilus_warn "Invalid thumbnailer directory: $directory"
    return 1
  fi
  if [[ -L "$target" || ( -e "$target" && ! -f "$target" ) ]]; then
    nautilus_warn "Invalid thumbnailer file: $target"
    return 1
  fi

  mkdir -p -- "$directory" || return 1
  temporary="$(mktemp "${directory}/.exe-thumbnailer.XXXXXX")" || return 1

  cat > "$temporary" <<EOF
[Thumbnailer Entry]
TryExec=exe-thumbnailer
Exec=exe-thumbnailer -s %s %i %o
MimeType=${ARCHMIND_NAUTILUS_MIME_TYPES}
EOF

  chmod 644 -- "$temporary"
  mv -f -- "$temporary" "$target"
  nautilus_ok "Executable thumbnailer configured."
}

nautilus_append_css() {
  local directory="${HOME}/.config/gtk-4.0"
  local target="${directory}/gtk.css"
  local temporary=""
  local backup_dir="${HOME}/ArchMind/Installer-Backups"

  if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
    nautilus_warn "Invalid GTK4 directory: $directory"
    return 1
  fi
  if [[ -L "$target" || ( -e "$target" && ! -f "$target" ) ]]; then
    nautilus_warn "Invalid CSS file: $target"
    return 1
  fi

  mkdir -p -- "$directory" || return 1

  if [[ -f "$target" ]] && grep -qxF "$ARCHMIND_NAUTILUS_MARKER" "$target"; then
    nautilus_ok "Thumbnail CSS was already configured."
    return 0
  fi

  temporary="$(mktemp "${directory}/.gtk.css.XXXXXX")" || return 1

  if [[ -f "$target" ]]; then
    [[ -w "$target" ]] || {
      rm -f -- "$temporary"
      nautilus_warn "Permission denied while updating: $target"
      return 1
    }
    mkdir -p -- "$backup_dir"
    cp -a -- "$target" "${backup_dir}/gtk.css-before-nautilus-$(date +'%Y%m%d-%H%M%S')"
    cp -- "$target" "$temporary"
    [[ ! -s "$temporary" ]] || printf '\n' >> "$temporary"
  fi

  cat >> "$temporary" <<EOF
${ARCHMIND_NAUTILUS_MARKER}
.nautilus-window.view .thumbnail {
    background: none;
    box-shadow: none;
}
${ARCHMIND_NAUTILUS_END}
EOF

  if [[ -f "$target" ]]; then
    chmod --reference="$target" "$temporary" 2>/dev/null || chmod 644 -- "$temporary"
  else
    chmod 644 -- "$temporary"
  fi
  mv -f -- "$temporary" "$target"
  nautilus_ok "The checkered thumbnail background was removed."
}

nautilus_set_sorting() {
  if ! nautilus_has gsettings; then
    nautilus_warn "gsettings not found; Nautilus sorting was not changed."
    return 1
  fi

  if ! gsettings list-schemas 2>/dev/null | grep -qxF org.gnome.nautilus.preferences; then
    nautilus_warn "The org.gnome.nautilus.preferences schema is unavailable."
    return 1
  fi

  gsettings set org.gnome.nautilus.preferences sort-directories-first true || {
    nautilus_warn "Could not place folders before files."
    return 1
  }
  nautilus_ok "Folders configured before files."
}

nautilus_refresh_thumbnails() {
  local cache="${HOME}/.cache/thumbnails"

  if [[ -d "$cache" && ! -L "$cache" ]]; then
    find "$cache" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || \
      nautilus_warn "Could not clear the entire thumbnail cache."
  fi

  nautilus -q >/dev/null 2>&1 || true
  nautilus_ok "Thumbnail cache prepared for rebuilding."
}

configure_nautilus() {
  local failed=0

  if (( EUID == 0 )); then
    nautilus_error "Run as your normal user, without sudo."
    return 1
  fi

  if ! nautilus_has nautilus; then
    nautilus_warn "Nautilus is not installed; integration skipped without interrupting ArchMind."
    return 0
  fi

  nautilus_info "Configuring Nautilus integration for Windows executables..."

  nautilus_install_dependencies || failed=1

  if ! nautilus_has exe-thumbnailer; then
    nautilus_warn "exe-thumbnailer is unavailable; .exe thumbnails will not be generated."
    failed=1
  fi

  nautilus_set_sorting || failed=1
  nautilus_write_thumbnailer || failed=1
  nautilus_append_css || failed=1
  nautilus_refresh_thumbnails

  if (( failed )); then
    nautilus_warn "Nautilus integration completed partially; the rest of ArchMind will continue normally."
  else
    nautilus_ok "Nautilus integration completed."
  fi

  # An optional integration must never stop a profile or restoration.
  return 0
}

case "${1:-}" in
  ""|--apply) configure_nautilus ;;
  --help|-h)
    printf '%s\n' \
      'Usage: configure-nautilus.sh [--apply]' \
      'Configure sorting, .exe thumbnails, and transparency in Nautilus.'
    ;;
  *)
    nautilus_error "Unknown option: $1"
    exit 2
    ;;
esac
