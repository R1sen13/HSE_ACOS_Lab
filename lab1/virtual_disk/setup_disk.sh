#!/usr/bin/env bash

set -e -u -o pipefail

SIZE_MB=${1:-2048}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"

MOUNT_DIR="$PROJECT_DIR/logs"
STATE_FILE="$SCRIPT_DIR/.log_disk_state"

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Error: Linux or Windows with WSL is required" >&2
    exit 1
fi

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
    SUDO="sudo"
fi

if [[ -n "$SUDO" ]] && ! command -v sudo > /dev/null 2>&1; then
    echo "Error: sudo is required but not found" >&2
    exit 1
fi

is_mounted() {
    mount | grep -F -q " on $MOUNT_DIR "
}

on_error() {
    echo "Setup failed. Run ./detach_disk.sh to clean up." >&2
}
trap on_error ERR

if [[ ! "$SIZE_MB" =~ ^[0-9]+$ ]] || (( SIZE_MB < 1 )); then
    echo "Error: SIZE_MB must be a positive integer" >&2
    exit 1
fi

if is_mounted; then
    echo "Error: $MOUNT_DIR is already mounted. Run ./detach_disk.sh first." >&2
    exit 1
fi

mkdir -p -- "$MOUNT_DIR"

IMG_FILE="$SCRIPT_DIR/log.img"
if [[ -e "$IMG_FILE" ]]; then
    echo "Error: image already exists: $IMG_FILE. Run ./detach_disk.sh first." >&2
    exit 1
fi

dd if=/dev/null of="$IMG_FILE" bs=1048576 seek="$SIZE_MB" count=0 2> /dev/null

DEV=$($SUDO losetup -f --show "$IMG_FILE")
printf '%s\n%s\n' "$IMG_FILE" "$DEV" > "$STATE_FILE"

$SUDO mkfs.ext4 -q "$DEV"
$SUDO mount "$DEV" "$MOUNT_DIR"
$SUDO chown "$(id -u):$(id -g)" "$MOUNT_DIR"

echo "Disk mounted at $MOUNT_DIR (${SIZE_MB} MB)."
