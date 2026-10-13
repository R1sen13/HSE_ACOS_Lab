#!/usr/bin/env bash

setup_env() {
  LOG_DIR="$TMP/log"
  BACKUP_DIR="$TMP/backup"
  PATHS_FILE="$TMP/paths.bin"

  rm -rf "$LOG_DIR" "$BACKUP_DIR" "$PATHS_FILE"
  mkdir -p "$LOG_DIR" "$BACKUP_DIR"
}

make_file() {
  local name="$1"
  local size_mb="$2"
  local date="$3"
  local path="$LOG_DIR/$name"
  local size_bytes=$((size_mb * 1024 * 1024))

  head -c "$size_bytes" /dev/zero > "$path"
  touch -d "$date" "$path"
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="$3"

  if [ "$actual" = "$expected" ]; then
    return 0
  fi

  echo "  $msg: expected '$expected', got '$actual'" >&2
  return 1
}

assert_exists() {
  local path="$1"
  local msg="$2"

  if [ -e "$path" ]; then
    return 0
  fi

  echo "  $msg: missing '$path'" >&2
  return 1
}

assert_missing() {
  local path="$1"
  local msg="$2"

  if [ ! -e "$path" ]; then
    return 0
  fi

  echo "  $msg: still exists '$path'" >&2
  return 1
}

report() {
  local name="$1"
  local status="$2"

  TOTAL=$((TOTAL + 1))

  if [ "$status" -eq 0 ]; then
    PASSED=$((PASSED + 1))
    echo "PASS: $name"
  else
    echo "FAIL: $name"
  fi
}
