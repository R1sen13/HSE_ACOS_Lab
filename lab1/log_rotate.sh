#bash


select_files() {
    local log_dir="$1"
    local required_bytes="$2"
    local output_file="$3"
    local total_size=0
    local entry
    local file
    local size

    if [[ ! -d "$log_dir" || ! "$required_bytes" =~ ^[0-9]+$ || -z "$output_file" ]]; then
        echo "Invalid arguments for select_files" >&2
        return 1
    fi

    : > "$output_file"

    while IFS= read -r -d '' entry; do
        file="${entry#* }"

        size=$(stat -c '%s' "$file") || return 1

        printf '%s\0' "$file" >> "$output_file"
        total_size=$((total_size + size))

        if (( total_size >= required_bytes )); then
            return 0
        fi
    done < <(
        find "$log_dir" -maxdepth 1 -type f -printf '%T@ %p\0' | sort --zero-terminated -n
    )

    echo "Not enough files to free the required space" >&2
    return 1
}

create_archive() {
    local backup_dir="$1"
    local output_file="$2"
    local timestamp
    local archive

    if [[ ! -d "$backup_dir" || ! -f "$output_file" ]]; then
        echo "Backup directory or selection file does not exist" >&2
        return 1
    fi

    timestamp=$(date '+%Y%m%d_%H%M%S')

    if [[ "${LAB1_MAX_COMPRESSION:-0}" == "1" ]]; then
        archive="$backup_dir/log_backup_${timestamp}.tar.lzma"
        tar --null -c --lzma -f "$archive" -T "$output_file" || {
            rm -f -- "$archive"
            return 1
        }
    else
        archive="$backup_dir/log_backup_${timestamp}.tar.gz"
        tar --null -czf "$archive" -T "$output_file" || {
            rm -f -- "$archive"
            return 1
        }
    fi

    printf '%s\n' "$archive"
}


verify_archive() {
    local archive="$1"

    if [[ ! -f "$archive" ]]; then
        echo "Archive does not exist: $archive" >&2
        return 1
    fi

    if [[ "$archive" == *.tar.lzma ]]; then
        tar --lzma -tf "$archive" > /dev/null 2>&1
    else
        tar -tzf "$archive" > /dev/null 2>&1
    fi
}


remove_archived_files() {
    local output_file="$1"
    local file

    if [[ ! -f "$output_file" ]]; then
        echo "Selection file does not exist" >&2
        return 1
    fi

    while IFS= read -r -d '' file; do
        rm -- "$file" || return 1
    done < "$output_file"
}