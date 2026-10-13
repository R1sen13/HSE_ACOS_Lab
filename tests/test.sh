#!/usr/bin/env bash
set -u

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$TEST_DIR/.." && pwd)
LIB_PATH="$ROOT_DIR/log_rotate.sh"

if [ ! -f "$LIB_PATH" ]; then
  echo "FAIL: log_rotate.sh not found: $LIB_PATH" >&2
  exit 1
fi

# shellcheck source=../log_rotate.sh
source "$LIB_PATH"
# shellcheck source=helpers.sh
source "$TEST_DIR/helpers.sh"
# shellcheck source=cases.sh
source "$TEST_DIR/cases.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASSED=0
TOTAL=0

run_case() {
  local name="$1"
  local status=0

  ( "$name" )
  status=$?

  report "$name" "$status"
}

run_case not_enough_space
run_case enough_space
run_case oldest_selected
run_case invalid_args
run_case spaces_in_names
run_case max_compression

echo "Passed: $PASSED/$TOTAL"

if [ "$PASSED" -eq "$TOTAL" ]; then
  exit 0
fi

exit 1
