#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -e -u -o pipefail
fi

log_dir=""
backup_dir=""
threshold=70
temp_dir=""

show_help() {
    echo "Usage: $0 -p LOG_DIR -b BACKUP_DIR [-x THRESHOLD]"
    echo "  -p LOG_DIR      Directory containing log files"
    echo "  -b BACKUP_DIR   Directory for backup archives"
    echo "  -x THRESHOLD    Maximum filesystem usage percentage (default: 70)"
    echo "  -h              Show this help"
}

file_size() {
    stat -c '%s' -- "$1"
}


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
        entry=${entry#* }
        size=${entry%% *}
        filepath=${entry#* }

        printf '%s\0' "$filepath" >> "$paths_file"
        total_size_bytes=$((total_size_bytes + size))

        if (( total_size_bytes >= target_bytes )); then
            return 0
        fi
    done < <(find "$log_dir" -maxdepth 1 -type f -printf '%T@ %s %p\0' | sort -zn)

    echo "Not enough files to free the required space" >&2
    return 1
}

create_archive() {
    local backup_dir="$1"
    local paths_file="$2"
    local timestamp
    local archive
    local filepath
    local files=()

    if [[ ! -d "$backup_dir" || ! -f "$paths_file" ]]; then
        echo "Backup directory or selection file does not exist" >&2
        return 1
    fi

    while IFS= read -r -d '' filepath; do
        files+=("$filepath")
    done < "$paths_file"

    if (( ${#files[@]} == 0 )); then
        echo "Selection file is empty" >&2
        return 1
    fi

    timestamp="$(date '+%Y%m%d_%H%M%S')_$$_${RANDOM}"

    if [[ "${LAB1_MAX_COMPRESSION:-0}" == "1" ]]; then
        if ! command -v xz > /dev/null 2>&1; then
            echo "Error: xz is required for LAB1_MAX_COMPRESSION=1" >&2
            return 1
        fi

        archive="$backup_dir/log_backup_${timestamp}.tar.lzma"
        (
            set -o pipefail
            tar -cf - "${files[@]}" | xz --format=lzma -9e -c > "$archive"
        ) || {
            rm -f -- "$archive"
            return 1
        }
    else
        archive="$backup_dir/log_backup_${timestamp}.tar.gz"
        (
            set -o pipefail
            tar -cf - "${files[@]}" | gzip -c > "$archive"
        ) || {
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
        (
            set -o pipefail
            xz -dc --format=lzma < "$archive" | tar -tf - > /dev/null 2>&1
        )
    else
        (
            set -o pipefail
            gzip -dc < "$archive" | tar -tf - > /dev/null 2>&1
        )
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
    done < "$paths_file"

    while IFS= read -r -d '' filepath; do
        if ! rm -- "$filepath"; then
            echo "Cannot remove file: $filepath" >&2
            return 1
        fi
    done < "$paths_file"
}

parse_arguments() {
    local opt

    while getopts ":p:x:b:h" opt; do
        case "$opt" in
            p)
                log_dir="$OPTARG"
                ;;
            x)
                threshold="$OPTARG"
                ;;
            b)
                backup_dir="$OPTARG"
                ;;
            h)
                show_help
                exit 0
                ;;
            :)
                echo "Error: option -$OPTARG requires an argument" >&2
                return 1
                ;;
            \?)
                echo "Error: unknown option -$OPTARG" >&2
                return 1
                ;;
        esac
    done

    shift $((OPTIND - 1))

    if (( $# > 0 )); then
        echo "Error: unexpected arguments: $*" >&2
        return 1
    fi
}

validate_arguments() {
    if [[ -z "$log_dir" ]]; then
        echo "Error: option -p LOG_DIR is required" >&2
        return 1
    fi

    if [[ -z "$backup_dir" ]]; then
        echo "Error: option -b BACKUP_DIR is required" >&2
        return 1
    fi

    if [[ ! "$threshold" =~ ^[0-9]+$ ]] ||
       (( threshold < 1 || threshold > 100 )); then
        echo "Error: threshold must be an integer between 1 and 100" >&2
        return 1
    fi
}

validate_directories() {
    local real_log_dir
    local real_backup_dir

    if [[ ! -d "$log_dir" ]]; then
        echo "Error: log directory does not exist: $log_dir" >&2
        return 1
    fi

    if [[ ! -r "$log_dir" || ! -x "$log_dir" ]]; then
        echo "Error: cannot access log directory: $log_dir" >&2
        return 1
    fi

    if [[ -z "$(find "$log_dir" -maxdepth 1 -type f -print -quit)" ]]; then
        echo "Error: no files found in log directory" >&2
        return 1
    fi

    if ! mkdir -p -- "$backup_dir"; then
        echo "Error: cannot create backup directory: $backup_dir" >&2
        return 1
    fi

    if [[ ! -w "$backup_dir" || ! -x "$backup_dir" ]]; then
        echo "Error: cannot write to backup directory: $backup_dir" >&2
        return 1
    fi

    real_log_dir=$(realpath -- "$log_dir") || {
        echo "Error: cannot resolve log directory path" >&2
        return 1
    }

    real_backup_dir=$(realpath -- "$backup_dir") || {
        echo "Error: cannot resolve backup directory path" >&2
        return 1
    }

    if [[ "$real_log_dir" == "$real_backup_dir" ]]; then
        echo "Error: log and backup directories must be different" >&2
        return 1
    fi
}

get_fs_usage() {
    local directory="$1"
    local stats
    local fs_size
    local fs_used

    stats=$(df -Pk "$directory" 2> /dev/null) || {
        echo "Error: cannot get filesystem usage for $directory" >&2
        return 1
    }

    stats=$(awk 'NR == 2 { printf "%.0f %.0f", $2 * 1024, $3 * 1024 }' <<< "$stats")
    read -r fs_size fs_used <<< "$stats"

    if [[ ! "$fs_size" =~ ^[0-9]+$ ||
          ! "$fs_used" =~ ^[0-9]+$ ]] ||
       (( fs_size <= 0 )); then
        echo "Error: invalid filesystem usage data" >&2
        return 1
    fi

    printf '%s %s\n' "$fs_size" "$fs_used"
}

rotate_logs() {
    local fs_size
    local current_bytes
    local current_percent
    local target_bytes
    local required_bytes
    local stats
    local paths_file
    local selected_count=0
    local selected_bytes=0
    local filepath
    local size
    local archive_path

    stats=$(get_fs_usage "$log_dir") || return 1
    read -r fs_size current_bytes <<< "$stats"

    current_percent=$((current_bytes * 100 / fs_size))
    target_bytes=$((fs_size * threshold / 100))
    required_bytes=$((current_bytes - target_bytes))

    echo "Current fill: ${current_percent}%"
    echo "Threshold: ${threshold}%"

    if (( current_bytes * 100 <= fs_size * threshold )); then
        echo "No rotation required."
        return 0
    fi

    if (( required_bytes <= 0 )); then
        required_bytes=1
    fi

    echo "Need to free at least ${required_bytes} bytes."

    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/log_rotate.XXXXXX") || {
        echo "Error: cannot create temporary directory" >&2
        return 1
    }

    paths_file="$temp_dir/selected_paths"

    trap 'rm -rf -- "$temp_dir"' EXIT

    if ! select_files "$log_dir" "$required_bytes" "$paths_file"; then
        echo "Error: failed to select files for archiving" >&2
        return 1
    fi

    while IFS= read -r -d '' filepath; do
        size=$(file_size "$filepath") || {
            echo "Error: cannot get file size: $filepath" >&2
            return 1
        }

        selected_count=$((selected_count + 1))
        selected_bytes=$((selected_bytes + size))
    done < "$paths_file"

    echo "Files to archive: $selected_count"
    echo "Archive input size: $selected_bytes bytes"

    archive_path=$(create_archive "$backup_dir" "$paths_file") || {
        echo "Error: failed to create archive" >&2
        return 1
    }

    echo "Archive created: $archive_path"

    if ! verify_archive "$archive_path"; then
        echo "Error: archive verification failed: $archive_path" >&2
        return 1
    fi

    echo "Archive verification successful."

    if ! remove_archived_files "$paths_file"; then
        echo "Error: failed to remove archived files" >&2
        return 1
    fi

    stats=$(get_fs_usage "$log_dir") || return 1
    read -r fs_size current_bytes <<< "$stats"

    current_percent=$((current_bytes * 100 / fs_size))

    echo "Final fill: ${current_percent}%"

    if (( current_bytes * 100 <= fs_size * threshold )); then
        echo "Log rotation completed successfully. Fill is within the threshold."
    else
        echo "Warning: fill is still above the threshold (${threshold}%)."
    fi

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    parse_arguments "$@" || exit 1
    validate_arguments || exit 1
    validate_directories || exit 1
    rotate_logs || exit 1
fi
