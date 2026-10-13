#!/usr/bin/env bash

archive_basenames() {
  local archive="$1"

  tar -tzf "$archive" | while IFS= read -r entry; do
    printf '%s\n' "${entry##*/}"
  done | sort
}

selected_basenames() {
  local paths_file="$1"
  local path

  while IFS= read -r -d '' path; do
    printf '%s\n' "${path##*/}"
  done < "$paths_file" | sort
}

assert_archive_names() {
  local archive="$1"
  local expected="$2"
  local actual

  actual=$(archive_basenames "$archive")
  assert_eq "$actual" "$expected" "archive content"
}

not_enough_space() {
  setup_env

  make_file "old.log" 300 "2024-01-01 00:00"
  make_file "new.log" 300 "2024-01-02 00:00"

  select_files "$LOG_DIR" "$((700 * 1024 * 1024))" "$PATHS_FILE" 2>"$TMP/stderr"
  local status=$?
  local first_archive

  first_archive=$(find "$BACKUP_DIR" -type f -print -quit)

  assert_eq "$status" "1" "select_files status" || return 1
  assert_eq "$first_archive" "" "archive count" || return 1
  assert_exists "$LOG_DIR/old.log" "old file kept" || return 1
  assert_exists "$LOG_DIR/new.log" "new file kept" || return 1
}

enough_space() {
  setup_env

  make_file "old-1.log" 160 "2024-01-01 00:00"
  make_file "old-2.log" 160 "2024-01-02 00:00"
  make_file "old-3.log" 160 "2024-01-03 00:00"
  make_file "new.log" 160 "2024-01-04 00:00"

  select_files "$LOG_DIR" "$((350 * 1024 * 1024))" "$PATHS_FILE" || return 1
  local selected
  selected=$(selected_basenames "$PATHS_FILE")

  local expected
  expected=$(printf '%s\n' "old-1.log" "old-2.log" "old-3.log" | sort)

  assert_eq "$selected" "$expected" "selected files" || return 1

  local archive
  archive=$(create_archive "$BACKUP_DIR" "$PATHS_FILE") || return 1

  verify_archive "$archive" || return 1
  assert_exists "$archive" "archive created" || return 1

  remove_archived_files "$PATHS_FILE" || return 1

  assert_missing "$LOG_DIR/old-1.log" "old-1 removed" || return 1
  assert_missing "$LOG_DIR/old-2.log" "old-2 removed" || return 1
  assert_missing "$LOG_DIR/old-3.log" "old-3 removed" || return 1
  assert_exists "$LOG_DIR/new.log" "new file kept" || return 1
}

oldest_selected() {
  setup_env

  make_file "oldest.log" 160 "2024-01-01 00:00"
  make_file "middle.log" 160 "2024-01-02 00:00"
  make_file "newer.log" 160 "2024-01-03 00:00"
  make_file "newest.log" 160 "2024-01-04 00:00"

  select_files "$LOG_DIR" "$((300 * 1024 * 1024))" "$PATHS_FILE" || return 1

  local archive
  archive=$(create_archive "$BACKUP_DIR" "$PATHS_FILE") || return 1

  local expected
  expected=$(printf '%s\n' "middle.log" "oldest.log" | sort)

  assert_archive_names "$archive" "$expected" || return 1
  assert_exists "$LOG_DIR/newer.log" "newer file kept" || return 1
  assert_exists "$LOG_DIR/newest.log" "newest file kept" || return 1
}

invalid_args() {
  setup_env

  make_file "one.log" 300 "2024-01-01 00:00"
  make_file "two.log" 300 "2024-01-02 00:00"

  select_files "$TMP/no-such-dir" "1" "$PATHS_FILE" 2>"$TMP/missing-dir.err"
  local missing_status=$?

  select_files "$LOG_DIR" "abc" "$PATHS_FILE" 2>"$TMP/bad-bytes.err"
  local bytes_status=$?

  if [ "$missing_status" -eq 0 ]; then
    echo "  missing directory returned success" >&2
    return 1
  fi

  if [ "$bytes_status" -eq 0 ]; then
    echo "  invalid REQUIRED_BYTES returned success" >&2
    return 1
  fi

  if [ ! -s "$TMP/missing-dir.err" ]; then
    echo "  missing directory stderr is empty" >&2
    return 1
  fi

  if [ ! -s "$TMP/bad-bytes.err" ]; then
    echo "  invalid REQUIRED_BYTES stderr is empty" >&2
    return 1
  fi
}

spaces_in_names() {
  setup_env

  make_file "old one.log" 160 "2024-01-01 00:00"
  make_file "old two.log" 160 "2024-01-02 00:00"
  make_file "old three.log" 160 "2024-01-03 00:00"
  make_file "new file.log" 160 "2024-01-04 00:00"

  select_files "$LOG_DIR" "$((350 * 1024 * 1024))" "$PATHS_FILE" || return 1

  local archive
  archive=$(create_archive "$BACKUP_DIR" "$PATHS_FILE") || return 1

  local expected
  expected=$(printf '%s\n' "old one.log" "old three.log" "old two.log" | sort)

  assert_archive_names "$archive" "$expected" || return 1

  remove_archived_files "$PATHS_FILE" || return 1

  assert_missing "$LOG_DIR/old one.log" "old one removed" || return 1
  assert_missing "$LOG_DIR/old two.log" "old two removed" || return 1
  assert_missing "$LOG_DIR/old three.log" "old three removed" || return 1
  assert_exists "$LOG_DIR/new file.log" "new file kept" || return 1
}

max_compression() {
  setup_env

  make_file "old-1.log" 160 "2024-01-01 00:00"
  make_file "old-2.log" 160 "2024-01-02 00:00"
  make_file "old-3.log" 160 "2024-01-03 00:00"
  make_file "new.log" 160 "2024-01-04 00:00"

  select_files "$LOG_DIR" "$((350 * 1024 * 1024))" "$PATHS_FILE" || return 1

  local archive
  archive=$(LAB1_MAX_COMPRESSION=1 create_archive "$BACKUP_DIR" "$PATHS_FILE") || return 1

  case "$archive" in
    *.tar.lzma) ;;
    *)
      echo "  archive extension is not .tar.lzma: $archive" >&2
      return 1
      ;;
  esac

  local file_type
  file_type=$(file "$archive")

  case "$file_type" in
    *LZMA*|*lzma*) ;;
    *)
      echo "  file does not report lzma: $file_type" >&2
      return 1
      ;;
  esac

  verify_archive "$archive" || return 1
}
