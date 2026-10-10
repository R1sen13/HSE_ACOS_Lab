#bash

select_files() {
    local log_dir="$1"
    local target_bytes="$2"
    local paths_file="$3"
    local total_size_bytes=0
    local entry
    local filepath
    local size

    if [[ ! -d "$log_dir" || ! "$target_bytes" =~ ^[0-9]+$ || -z "$paths_file" ]]; then
        echo "Invalid arguments for select_files" >&2
        return 1
    fi

    : > "$paths_file"

    while IFS= read -r -d '' entry; do
        filepath="${entry#* }"

        size=$(stat -c '%s' "$filepath") || return 1

        printf '%s\0' "$filepath" >> "$paths_file"
        total_size_bytes=$((total_size_bytes + size))

        if (( total_size_bytes >= target_bytes )); then
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
    local paths_file="$2"
    local timestamp
    local archive

    if [[ ! -d "$backup_dir" || ! -f "$paths_file" ]]; then
        echo "Backup directory or selection file does not exist" >&2
        return 1
    fi

    timestamp=$(date '+%Y%m%d_%H%M%S_%N')

    if [[ "${LAB1_MAX_COMPRESSION:-0}" == "1" ]]; then
        archive="$backup_dir/log_backup_${timestamp}.tar.lzma"
        tar --null -c --lzma -f "$archive" -T "$paths_file" || {
            rm -f -- "$archive"
            return 1
        }
    else
        archive="$backup_dir/log_backup_${timestamp}.tar.gz"
        tar --null -c -z -f "$archive" -T "$paths_file" || {
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
        tar -t --lzma -f "$archive" > /dev/null 2>&1
    else
        tar -t -z -f "$archive" > /dev/null 2>&1
    fi
}


remove_archived_files() {
    local paths_file="$1"
    local filepath

    if [[ ! -f "$paths_file" ]]; then
        echo "Paths file does not exist" >&2
        return 1
    fi

    while IFS= read -r -d '' filepath; do
        if [[ ! -e "$filepath" ]]; then
            echo "File does not exist: $filepath" >&2
            return 1
        fi
        if [[ ! -w "$filepath" ]]; then
            echo "No write/delete permission: $filepath" >&2
            return 1
        fi

    done < "$paths_file"

    while IFS= read -r -d '' filepath; do
        rm -- "$filepath" || return 1
    done < "$paths_file"
}