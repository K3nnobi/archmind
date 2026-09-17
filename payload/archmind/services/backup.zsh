#!/usr/bin/env zsh

typeset -g ARCHMIND_BACKUP_DIR="${ARCHMIND_BACKUP_DIR:-$HOME/ArchMind/Backups}"

backup_find_files() {
    emulate -L zsh
    setopt localoptions nullglob

    local -a files
    files=("$ARCHMIND_BACKUP_DIR"/*.archmind(N.om))

    print -rl -- "${files[@]}"
}

backup_get_latest() {
    emulate -L zsh
    setopt localoptions nullglob

    local -a files
    files=("$ARCHMIND_BACKUP_DIR"/*.archmind(N.om))

    (( ${#files[@]} > 0 )) || return 1

    print -r -- "$files[1]"
}

backup_human_size() {
    emulate -L zsh

    local file="${1:-}"

    [[ -f "$file" ]] || {
        print -r -- "Unavailable"
        return 1
    }

    if command -v numfmt >/dev/null 2>&1; then
        stat -c '%s' "$file" 2>/dev/null \
            | numfmt --to=iec-i --suffix=B
    else
        du -h "$file" 2>/dev/null | awk '{print $1}'
    fi
}

backup_file_date() {
    emulate -L zsh

    local file="${1:-}"

    [[ -f "$file" ]] || {
        print -r -- "Unavailable"
        return 1
    }

    date -d "@$(stat -c '%Y' "$file")" '+%d/%m/%Y %H:%M:%S' 2>/dev/null \
        || print -r -- "Unavailable"
}

backup_collect_summary() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga BACKUP_SUMMARY_LINES

    local latest=""
    local total=0
    local size=""
    local date_value=""

    total="$(backup_find_files | sed '/^$/d' | wc -l | tr -d ' ')"
    [[ "$total" == <-> ]] || total=0

    if latest="$(backup_get_latest 2>/dev/null)"; then
        size="$(backup_human_size "$latest")"
        date_value="$(backup_file_date "$latest")"

        BACKUP_SUMMARY_LINES=(
            "Directory .......... ${ARCHMIND_BACKUP_DIR}"
            "Backups found  ${total}"
            ""
            "Latest:"
            "File ............. ${latest:t}"
            "Date ................ ${date_value}"
            "Size ............. ${size}"
        )
    else
        BACKUP_SUMMARY_LINES=(
            "Directory .......... ${ARCHMIND_BACKUP_DIR}"
            "Backups found  0"
            ""
            "No .archmind files were found."
        )
    fi
}

backup_list_information() {
    emulate -L zsh
    setopt localoptions typesetsilent nullglob

    typeset -ga BACKUP_LIST_LINES

    local -a files
    local file=""
    local counter=1
    local size=""
    local date_value=""

    files=("$ARCHMIND_BACKUP_DIR"/*.archmind(N.om))
    BACKUP_LIST_LINES=()

    if (( ${#files[@]} == 0 )); then
        BACKUP_LIST_LINES=(
            "No backups found in:"
            "$ARCHMIND_BACKUP_DIR"
        )
        return 0
    fi

    BACKUP_LIST_LINES+=(
        "Backups found: ${#files[@]}"
        ""
    )

    for file in "${files[@]}"; do
        size="$(backup_human_size "$file")"
        date_value="$(backup_file_date "$file")"

        BACKUP_LIST_LINES+=(
            "${counter}. ${file:t}"
            "   Date: ${date_value}"
            "   Size: ${size}"
            ""
        )

        (( counter++ ))

        # Avoid an excessively large window.
        (( counter > 10 )) && {
            BACKUP_LIST_LINES+=(
                "Showing the nine most recent backups."
            )
            break
        }
    done
}

backup_detect_archive_type() {
    emulate -L zsh

    local file="${1:-}"
    local description=""

    [[ -f "$file" ]] || return 1

    description="$(file -b "$file" 2>/dev/null)"

    case "$description" in
        *gzip*)
            print -r -- "gzip"
            ;;
        *XZ*|*xz*)
            print -r -- "xz"
            ;;
        *Zstandard*|*zstd*)
            print -r -- "zstd"
            ;;
        *tar*)
            print -r -- "tar"
            ;;
        *Zip*)
            print -r -- "zip"
            ;;
        *)
            print -r -- "unknown"
            ;;
    esac
}

backup_extract_to_temp() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local file="${1:-}"
    local destination="${2:-}"
    local archive_type=""

    [[ -f "$file" && -d "$destination" ]] || return 1

    archive_type="$(backup_detect_archive_type "$file")"

    case "$archive_type" in
        gzip|xz|zstd|tar)
            tar -xf "$file" -C "$destination" >/dev/null 2>&1
            ;;

        zip)
            command -v unzip >/dev/null 2>&1 || return 1
            unzip -q "$file" -d "$destination" >/dev/null 2>&1
            ;;

        *)
            return 1
            ;;
    esac
}

backup_find_metadata_root() {
    emulate -L zsh

    local directory="${1:-}"
    local result=""

    [[ -d "$directory" ]] || return 1

    if [[ -f "$directory/manifest.json" || -f "$directory/manifest.txt" || -f "$directory/checksums.sha256" ]]; then
        print -r -- "$directory"
        return 0
    fi

    result="$(
        find "$directory" -maxdepth 3 -type f \
            \( -name 'manifest.json' -o -name 'manifest.txt' -o -name 'checksums.sha256' \) \
            -printf '%h\n' 2>/dev/null \
            | head -n 1
    )"

    [[ -n "$result" ]] || return 1
    print -r -- "$result"
}

backup_validate_latest() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga BACKUP_VALIDATION_LINES

    local latest=""
    local temp_dir=""
    local root=""
    local archive_type=""
    local manifest_status="Missing"
    local checksum_status="Missing"
    local checksum_result="Not checked"
    local extraction_status="Failed"
    local overall_status="Invalid"

    BACKUP_VALIDATION_LINES=()

    if ! latest="$(backup_get_latest 2>/dev/null)"; then
        BACKUP_VALIDATION_LINES=(
            "No .archmind backup was found."
            "Directory: $ARCHMIND_BACKUP_DIR"
        )
        return 1
    fi

    archive_type="$(backup_detect_archive_type "$latest")"
    temp_dir="$(mktemp -d -t archmind-validate.XXXXXX)" || return 1

    if backup_extract_to_temp "$latest" "$temp_dir"; then
        extraction_status="OK"

        if root="$(backup_find_metadata_root "$temp_dir" 2>/dev/null)"; then
            [[ -f "$root/manifest.json" || -f "$root/manifest.txt" ]] && manifest_status="Found"

            if [[ -f "$root/checksums.sha256" ]]; then
                checksum_status="Found"

                if (
                    cd "$root" || exit 1
                    sha256sum -c checksums.sha256 >/dev/null 2>&1
                ); then
                    checksum_result="OK"
                else
                    checksum_result="Failed"
                fi
            fi
        fi
    fi

    if [[ "$extraction_status" == "OK" \
        && "$manifest_status" == "Found" \
        && "$checksum_result" == "OK" ]]; then
        overall_status="Valid"
    elif [[ "$extraction_status" == "OK" \
        && "$manifest_status" == "Found" \
        && "$checksum_status" == "Missing" ]]; then
        overall_status="Valid structure; checksums unavailable"
    fi

    BACKUP_VALIDATION_LINES=(
        "File ............. ${latest:t}"
        "Format ............. ${archive_type}"
        "Extraction ............ ${extraction_status}"
        "Manifest ........... ${manifest_status}"
        "Checksums ........... ${checksum_status}"
        "Verification ......... ${checksum_result}"
        ""
        "Final result ..... ${overall_status}"
    )

    rm -rf -- "$temp_dir"

    [[ "$overall_status" == "Valid" ]]
}

backup_read_manifest() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga BACKUP_MANIFEST_LINES

    local latest=""
    local temp_dir=""
    local root=""
    local manifest=""

    BACKUP_MANIFEST_LINES=()

    if ! latest="$(backup_get_latest 2>/dev/null)"; then
        BACKUP_MANIFEST_LINES=("No backup was found.")
        return 1
    fi

    temp_dir="$(mktemp -d -t archmind-manifest.XXXXXX)" || return 1

    if ! backup_extract_to_temp "$latest" "$temp_dir"; then
        BACKUP_MANIFEST_LINES=(
            "Could not open the backup:"
            "${latest:t}"
        )
        rm -rf -- "$temp_dir"
        return 1
    fi

    if ! root="$(backup_find_metadata_root "$temp_dir" 2>/dev/null)"; then
        BACKUP_MANIFEST_LINES=(
            "Manifest not found in backup."
        )
        rm -rf -- "$temp_dir"
        return 1
    fi

    if [[ -f "$root/manifest.json" ]]; then
        manifest="$root/manifest.json"
    else
        manifest="$root/manifest.txt"
    fi

    if [[ ! -f "$manifest" ]]; then
        BACKUP_MANIFEST_LINES=(
            "No manifest.json or manifest.txt file exists."
        )
        rm -rf -- "$temp_dir"
        return 1
    fi

    BACKUP_MANIFEST_LINES+=(
        "Backup: ${latest:t}"
        ""
    )

    while IFS= read -r line; do
        BACKUP_MANIFEST_LINES+=("$line")
        (( ${#BACKUP_MANIFEST_LINES[@]} >= 20 )) && {
            BACKUP_MANIFEST_LINES+=(
                ""
                "Content limited to the first lines of the manifest."
            )
            break
        }
    done < "$manifest"

    rm -rf -- "$temp_dir"
}
