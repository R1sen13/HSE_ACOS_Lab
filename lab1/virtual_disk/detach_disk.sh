#!/usr/bin/env bash
set -e -u -o pipefail

BASE_DIR="$(pwd)"
MOUNT_DIR="${BASE_DIR}/logs"
IMG_FILE="${MOUNT_DIR}/log.img"

if mountpoint -q "$MOUNT_DIR"; then
    EXTRA_FILES=$(sudo find "$MOUNT_DIR" -mindepth 1 ! -name "log.img" ! -name "lost+found")

    if [ -n "$EXTRA_FILES" ]; then
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

if mountpoint -q "$MOUNT_DIR"; then
    if ! sudo umount "$MOUNT_DIR" 2>/dev/null; then
        if command -v fuser &> /dev/null; then
            sudo fuser -k -9 -m "$MOUNT_DIR" || true
            sleep 1
        fi        
        sudo umount -l "$MOUNT_DIR"
    fi
fi

if [ -f "$IMG_FILE" ]; then
    LOOP_DEV=$(sudo losetup -j "$IMG_FILE" 2>/dev/null | awk -F: '{print $1}')
    
    if [ -n "$LOOP_DEV" ]; then
        sudo losetup -d "$LOOP_DEV"
    fi

    rm "$IMG_FILE"
    rmdir logs --ignore-fail-on-non-empty 2>/dev/null || true
    echo "Cleanup complete."
fi
