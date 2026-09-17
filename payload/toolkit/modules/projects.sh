#!/usr/bin/env bash

project_backup() {
  mkdir -p "$ARCHMIND_PROJECT_DIR"

  local stamp archive
  stamp="$(date +'%Y%m%d-%H%M%S')"
  archive="${ARCHMIND_BACKUP_DIR}/ArchMind-project-${stamp}.archmind"

  if [[ -z "$(find "$ARCHMIND_PROJECT_DIR" -mindepth 1 -print -quit)" ]]; then
    ui_warn "The project directory is empty: $ARCHMIND_PROJECT_DIR"
    return 0
  fi

  ui_info "Saving the entire ArchMind project..."

  local work
  work="$(mktemp -d "${ARCHMIND_TEMP_DIR}/project.XXXXXX")"
  mkdir -p "${work}/project"
  cp -a "${ARCHMIND_PROJECT_DIR}/." "${work}/project/"

  cat > "${work}/manifest.json" <<EOF
{
  "format": "archmind-project",
  "version": "2.0.0",
  "created": "$(date --iso-8601=seconds)"
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

  ui_ok "Project saved: $archive"
}

project_restore() {
  local backup
  backup="$(
    find "$ARCHMIND_BACKUP_DIR" -maxdepth 1 -type f \
      -name 'ArchMind-project-*.archmind' \
      -printf '%T@ %p\n' 2>/dev/null \
      | sort -nr \
      | head -n1 \
      | cut -d' ' -f2-
  )"

  [[ -n "$backup" ]] || {
    ui_error "No project backup was found."
    return 1
  }

  ui_info "Project backup: $backup"
  confirm "Replace the current project contents?" || return 0

  local extracted safety
  extracted="$(extract_archmind_backup "$backup")"
  safety="${ARCHMIND_BACKUP_DIR}/project-safety-$(date +'%Y%m%d-%H%M%S')"

  if [[ -n "$(find "$ARCHMIND_PROJECT_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    mkdir -p "$safety"
    cp -a "${ARCHMIND_PROJECT_DIR}/." "$safety/"
  ui_ok "Safety copy: $safety"
  fi

  rm -rf "${ARCHMIND_PROJECT_DIR:?}/"*
  cp -a "${extracted}/project/." "$ARCHMIND_PROJECT_DIR/"
  rm -rf "$extracted"

  ui_ok "ArchMind project restored."
}
