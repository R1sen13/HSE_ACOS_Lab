#!/usr/bin/env bash
#
# Reverts setup_disk.sh: unmounts <project>/logs, detaches the device,
# removes the image. Supported: Linux, macOS, FreeBSD.

set -e -u -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"

MOUNT_DIR="$PROJECT_DIR/logs"
STATE_FILE="$SCRIPT_DIR/.log_disk_state"
OS="$(uname -s)"

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
    case "$OS" in
        Darwin) IMG_FILE="$SCRIPT_DIR/log.dmg" ;;
        *)      IMG_FILE="$SCRIPT_DIR/log.img" ;;
    esac
fi

# Ask before destroying anything that is stored on the virtual disk.
if is_mounted; then
    EXTRA_FILES=$(ls -A "$MOUNT_DIR" |
        grep -v -E '^(lost\+found|\.fseventsd|\.Spotlight-V100|\.Trashes|\.TemporaryItems)$' ||
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

# Unmount.
if is_mounted; then
    case "$OS" in
        Darwin)
            $SUDO hdiutil detach -quiet "$MOUNT_DIR" ||
                $SUDO hdiutil detach -quiet -force "$MOUNT_DIR"
            ;;
        Linux)
            if ! $SUDO umount "$MOUNT_DIR"; then
                echo "Mount point is busy, using lazy unmount."
                $SUDO umount -l "$MOUNT_DIR"
            fi
            ;;
        *)
            $SUDO umount "$MOUNT_DIR" || $SUDO umount -f "$MOUNT_DIR"
            ;;
    esac
fi

# Detach the block device.
case "$OS" in
    Linux)
        if [[ -f "$IMG_FILE" ]] && command -v losetup > /dev/null 2>&1; then
            for LOOP_DEV in $($SUDO losetup -j "$IMG_FILE" | awk -F: '{print $1}'); do
                $SUDO losetup -d "$LOOP_DEV"
            done
        fi
        ;;
    FreeBSD)
        if [[ -n "$DEV" ]]; then
            $SUDO mdconfig -d -u "$DEV"
        fi
        ;;
esac

if [[ -f "$IMG_FILE" ]]; then
    rm -- "$IMG_FILE"
    echo "Disk image removed."
fi

rm -f -- "$STATE_FILE"

# rmdir (not rm -rf): refuses to touch a directory that still has content.
if [[ -d "$MOUNT_DIR" ]] && ! is_mounted; then
    rmdir "$MOUNT_DIR" 2> /dev/null ||
        echo "Note: $MOUNT_DIR is not empty, left in place."
fi

echo "Cleanup complete."
