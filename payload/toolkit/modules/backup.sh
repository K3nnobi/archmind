#!/usr/bin/env bash

capture_packages() {
  local target="$1"
  mkdir -p "$target"

  pacman -Q > "${target}/pacman-all.txt"
  pacman -Qqe > "${target}/pacman-explicit.txt"
  pacman -Qqen > "${target}/pacman-native.txt"
  pacman -Qqem > "${target}/pacman-aur.txt"

  has flatpak && \
    flatpak list --app --columns=application \
      > "${target}/flatpak-apps.txt" 2>/dev/null || true
}

capture_configs() {
  local target="$1"
  mkdir -p "$target"

  local file
  for file in \
    .zshrc .zprofile .zshenv .p10k.zsh .zsh_aliases \
    .bashrc .bash_profile .profile .gitconfig; do
    [[ -e "${HOME}/${file}" ]] || continue
    case "$file" in
      .zsh_aliases|.p10k.zsh) cp -aL -- "${HOME}/${file}" "$target/" ;;
      *) cp -a -- "${HOME}/${file}" "$target/" ;;
    esac
  done

  if [[ -d "$ARCHMIND_CONFIG_DIR" ]]; then
    mkdir -p "${target}/archmind-config"
    cp -a -- "$ARCHMIND_CONFIG_DIR/." "${target}/archmind-config/"
  fi

  if [[ -f "$ARCHMIND_CORE_DIR/tools/doctor-report.py" ]] && has python3; then
    python3 -B "$ARCHMIND_CORE_DIR/tools/doctor-report.py" --export "$target/archmind-doctor-reports" || \
      ui_warn "Doctor reports could not be fully included in the backup."
  elif [[ -d "$ARCHMIND_LOG_DIR/Doctor" ]]; then
    ui_warn "Doctor reports were not backed up: the report helper or Python is missing."
  fi

  if [[ -d "${HOME}/.config" ]]; then
    mkdir -p "${target}/.config"

    if has rsync; then
      rsync -a \
        --exclude='archmind/' \
        --exclude='Cache/' \
        --exclude='cache/' \
        --exclude='GPUCache/' \
        --exclude='Code Cache/' \
        --exclude='logs/' \
        --exclude='google-chrome/' \
        --exclude='chromium/' \
        --exclude='discord/' \
        "${HOME}/.config/" "${target}/.config/"
    else
      local config_item config_name
      while IFS= read -r -d '' config_item; do
        config_name="$(basename "$config_item")"
        [[ "$config_name" == "archmind" ]] && continue
        cp -a -- "$config_item" "${target}/.config/"
      done < <(find "${HOME}/.config" -mindepth 1 -maxdepth 1 -print0)
    fi
  fi

  local path
  for path in \
    .themes .icons .fonts \
    .local/share/themes \
    .local/share/icons \
    .local/share/fonts \
    .local/share/thumbnailers \
    .local/bin; do
    if [[ "$path" == ".local/bin" && -d "${HOME}/${path}" ]]; then
      mkdir -p "${target}/${path}"
      local bin_item bin_name
      while IFS= read -r -d '' bin_item; do
        bin_name="$(basename "$bin_item")"
        [[ "$bin_name" == "archmind" || "$bin_name" == "archmind-console" || "$bin_name" == "archmind-monitor" ]] && continue
        cp -a -- "$bin_item" "${target}/${path}/"
      done < <(find "${HOME}/${path}" -mindepth 1 -maxdepth 1 -print0)
    elif [[ -e "${HOME}/${path}" ]]; then
      mkdir -p "$(dirname "${target}/${path}")"
      cp -a "${HOME}/${path}" "${target}/${path}"
    fi
  done
}

capture_gnome() {
  local target="$1"
  mkdir -p "${target}/extensions" "${target}/dconf"

  if [[ -d "${HOME}/.local/share/gnome-shell/extensions" ]]; then
    cp -a "${HOME}/.local/share/gnome-shell/extensions/." \
      "${target}/extensions/"
  fi

  if has gnome-extensions; then
    gnome-extensions list > "${target}/extensions-all.txt"
    gnome-extensions list --enabled > "${target}/extensions-enabled.txt"
    gnome-extensions list --disabled > "${target}/extensions-disabled.txt"
  fi

  if has dconf; then
    dconf dump /org/gnome/shell/ > "${target}/dconf/gnome-shell.dconf"
    dconf dump /org/gnome/desktop/interface/ > "${target}/dconf/interface.dconf"
    dconf dump /org/gnome/desktop/background/ > "${target}/dconf/background.dconf"
  fi
}

backup_create() {
  require_arch || return 1

  local mode="$1"
  local stamp work archive
  stamp="$(date +'%Y%m%d-%H%M%S')"
  work="$(mktemp -d "${ARCHMIND_TEMP_DIR}/backup.XXXXXX")"
  archive="${ARCHMIND_BACKUP_DIR}/ArchMind-${mode}-${stamp}.archmind"

  ui_info "Creating backup: ${mode}"

  case "$mode" in
    complete)
      capture_configs "${work}/configs"
      capture_gnome "${work}/gnome"
      capture_packages "${work}/packages"
      ;;
    gnome)
      capture_gnome "${work}/gnome"
      ;;
    packages)
      capture_packages "${work}/packages"
      ;;
    configs)
      capture_configs "${work}/configs"
      ;;
  esac

  cat > "${work}/manifest.json" <<EOF
{
  "format": "archmind",
  "version": "2.0.0",
  "mode": "${mode}",
  "created": "$(date --iso-8601=seconds)",
  "hostname": "${HOSTNAME:-unknown}",
  "user": "${USER}"
}
EOF

  (
    cd "$work"
    find . -type f ! -name checksums.sha256 -print0 \
      | sort -z \
      | xargs -0 sha256sum > checksums.sha256
  )

  tar -C "$work" -caf "$archive" .
  sha256sum "$archive" > "${archive}.sha256"
  rm -rf "$work"

  ui_ok "Backup criado: $archive"
}

backup_list() {
  local found=0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    found=1
    echo "$file"
  done < <(find "$ARCHMIND_BACKUP_DIR" -maxdepth 1 -type f -name '*.archmind' | sort)

  [[ "$found" -eq 1 ]] || ui_warn "No backup found."
}
