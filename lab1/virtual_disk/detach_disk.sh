#!/usr/bin/env bash

set -e -u -o pipefail

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

IMG_FILE=""
DEV=""

if [[ -f "$STATE_FILE" ]]; then
    {
        IFS= read -r IMG_FILE || true
        IFS= read -r DEV || true
    } < "$STATE_FILE"
fi

if [[ -z "$IMG_FILE" ]]; then
    IMG_FILE="$SCRIPT_DIR/log.img"
fi

if is_mounted; then
    EXTRA_FILES=$(ls -A "$MOUNT_DIR" |
        grep -v -x 'lost+found' ||
        true)

    if [[ -n "$EXTRA_FILES" ]]; then
        echo "WARNING: The following files/directories will be deleted:"
        echo "$EXTRA_FILES"
        echo -n "Do you want to proceed? [y/N]: "

        read -r ANSWER < /dev/tty
        if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled. Files are safe."
            exit 0
        fi
    fi
fi

if is_mounted; then
    if ! $SUDO umount "$MOUNT_DIR"; then
        echo "Mount point is busy, using lazy unmount."
        $SUDO umount -l "$MOUNT_DIR"
    fi
fi

if [[ -f "$IMG_FILE" ]] && command -v losetup > /dev/null 2>&1; then
    for LOOP_DEV in $($SUDO losetup -j "$IMG_FILE" | awk -F: '{print $1}'); do
        $SUDO losetup -d "$LOOP_DEV"
    done
fi

if [[ -f "$IMG_FILE" ]]; then
    rm -- "$IMG_FILE"
    echo "Disk image removed."
fi

rm -f -- "$STATE_FILE"

if [[ -d "$MOUNT_DIR" ]] && ! is_mounted; then
    rmdir "$MOUNT_DIR" 2> /dev/null ||
        echo "Note: $MOUNT_DIR is not empty, left in place."
fi

echo "Cleanup complete."
