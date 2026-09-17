#!/usr/bin/env bash
set -u

file="${1:-}"

if [[ ! -f "$file" ]]; then
  printf 'Invalid or missing file.\n'
  read -r -p 'Press Enter to close...' _
  exit 1
fi

printf '\nSelected file:\n%s\n\n' "$file"
printf 'WARNING: executable files can modify the system.\n'
read -r -p 'Do you really want to run it? [y/N]: ' answer

case "$answer" in
  y|Y|yes|YES|Yes)
    cd -- "$(dirname -- "$file")" || exit 1
    chmod u+x -- "$file" || exit 1
    "./$(basename -- "$file")"
    status=$?
    ;;
  *)
    printf 'Execution cancelled.\n'
    status=0
    ;;
esac

printf '\nProcess finished with exit code: %s\n' "$status"
read -r -p 'Press Enter to close...' _
exit "$status"
