#!/usr/bin/env bash

set -e -u -o pipefail

log_dir=""
backup_dir=""
threshold=70
limit_bytes=""
temp_dir=""

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
    done < "$paths_file"

    while IFS= read -r -d '' filepath; do
        if ! rm -- "$filepath"; then
        	echo "Cannot remove file: $filepath" >&2
        	return 1
    	fi
    done < "$paths_file"
}

get_log_size() {
    local directory="$1"
    local total_size_bytes=0
    local size

    while IFS= read -r size; do
        total_size_bytes=$((total_size_bytes + size))
    done < <(
        find "$directory" -maxdepth 1 -type f -printf '%s\n'
    )

    echo "$total_size_bytes"
}

parse_arguments() {
    OPTIND=1

    while getopts ":p:x:b:s:h" opt; do
        case "$opt" in
            p) log_dir="$OPTARG" ;;
            x) threshold="$OPTARG" ;;
            b) backup_dir="$OPTARG" ;;
            s) limit_bytes="$OPTARG" ;;
            h)
                echo "Usage: $0 -p LOG_DIR -b BACKUP_DIR [-x THRESHOLD] [-s LIMIT_BYTES]"
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
    if [[ -z "$log_dir" || -z "$backup_dir" ]]; then
        echo "Error: options -p and -b are required" >&2
        return 1
    fi

    if [[ ! "$threshold" =~ ^[0-9]+$ ]]; then
        echo "Error: threshold must be an integer from 1 to 100" >&2
        return 1
    fi

    threshold=$((10#$threshold))

    if (( threshold < 1 || threshold > 100 )); then
        echo "Error: threshold must be an integer from 1 to 100" >&2
        return 1
    fi

    if [[ -n "$limit_bytes" ]]; then
        if [[ ! "$limit_bytes" =~ ^[0-9]+$ ]]; then
            echo "Error: -s must be a positive integer in bytes" >&2
            return 1
        fi

        limit_bytes=$((10#$limit_bytes))

        if (( limit_bytes <= 0 )); then
            echo "Error: -s must be a positive integer in bytes" >&2
            return 1
        fi
    fi
}

validate_directories() {
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

    local real_log_dir
    local real_backup_dir

    real_log_dir=$(realpath "$log_dir") || {
        echo "Error: cannot resolve log directory path" >&2
        return 1
    }

    real_backup_dir=$(realpath "$backup_dir") || {
        echo "Error: cannot resolve backup directory path" >&2
        return 1
    }

    if [[ "$real_log_dir" == "$real_backup_dir" ]]; then
        echo "Error: log and backup directories must be different" >&2
        return 1
    fi
}

get_limit_bytes() {
    local filesystem_size

    if [[ -n "$limit_bytes" ]]; then
        echo "$limit_bytes"
        return 0
    fi

    filesystem_size=$(df -B1 --output=size "$log_dir" | tail -n 1 | tr -d ' ')

    if [[ ! "$filesystem_size" =~ ^[0-9]+$ ]] ||
       (( filesystem_size <= 0 )); then
        echo "Error: cannot determine file system size" >&2
        return 1
    fi

    echo "$filesystem_size"
}

rotate_logs() {
    local current_bytes
    local current_percent
    local target_bytes
    local required_bytes
    local paths_file
    local selected_count=0
    local selected_bytes=0
    local filepath
    local size
    local archive_path

    current_bytes=$(get_log_size "$log_dir") || return 1
    current_percent=$((current_bytes * 100 / limit_bytes))

    echo "Current fill: $current_percent%"
    echo "Threshold: $threshold%"

    if (( current_bytes * 100 <= limit_bytes * threshold )); then
        echo "No rotation required."
        return 0
    fi

    target_bytes=$((limit_bytes * threshold / 100))
    required_bytes=$((current_bytes - target_bytes))

    echo "Need to free at least $required_bytes bytes."

    temp_dir=$(mktemp -d) || {
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
        size=$(stat -c '%s' "$filepath") || {
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

    current_bytes=$(get_log_size "$log_dir") || return 1
    current_percent=$((current_bytes * 100 / limit_bytes))

    echo "Final fill: $current_percent%"
    echo "Rotation completed successfully."
}

parse_arguments "$@" || exit 1
validate_arguments || exit 1
validate_directories || exit 1

limit_bytes=$(get_limit_bytes) || exit 1

rotate_logs || exit 1
