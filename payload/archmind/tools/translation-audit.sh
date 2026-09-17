#!/usr/bin/env bash

set -euo pipefail

AUDITOR="$HOME/ArchMind/System/Core/tools/translation-audit.py"

if [[ ! -x "$AUDITOR" ]]; then
    printf 'Error: translation auditor not found:\n%s\n' "$AUDITOR" >&2
    exit 1
fi

exec python3 "$AUDITOR" "$@"
