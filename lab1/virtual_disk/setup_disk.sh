#!/usr/bin/env bash
#
# Creates a small separate filesystem mounted at <project>/logs.
# Supported: Linux (loop + ext4), macOS (hdiutil), FreeBSD (mdconfig + UFS).
# Usage: ./setup_disk.sh [SIZE_MB]   (default 2048)

set -e -u -o pipefail

SIZE_MB=${1:-2048}

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

on_error() {
    echo "Setup failed. Run ./detach_disk.sh to clean up." >&2
}
trap on_error ERR

if [[ ! "$SIZE_MB" =~ ^[0-9]+$ ]] || (( SIZE_MB < 1 )); then
    echo "Error: SIZE_MB must be a positive integer" >&2
    exit 1
fi

case "$OS" in
    Linux|Darwin|FreeBSD) ;;
    *)
        echo "Error: unsupported OS: $OS (supported: Linux, Darwin, FreeBSD)" >&2
        exit 1
        ;;
esac

if is_mounted; then
    echo "Error: $MOUNT_DIR is already mounted. Run ./detach_disk.sh first." >&2
    exit 1
fi

mkdir -p -- "$MOUNT_DIR"

# Sparse image file: fast to create and works with GNU and BSD dd.
make_image() {
    if [[ -e "$1" ]]; then
        echo "Error: image already exists: $1. Run ./detach_disk.sh first." >&2
        exit 1
    fi
    dd if=/dev/null of="$1" bs=1048576 seek="$SIZE_MB" count=0 2> /dev/null
}

case "$OS" in
    Linux)
        IMG_FILE="$SCRIPT_DIR/log.img"
        make_image "$IMG_FILE"

        DEV=$($SUDO losetup -f --show "$IMG_FILE")
        printf '%s\n%s\n' "$IMG_FILE" "$DEV" > "$STATE_FILE"

        $SUDO mkfs.ext4 -q "$DEV"
        $SUDO mount "$DEV" "$MOUNT_DIR"
        $SUDO chown "$(id -u):$(id -g)" "$MOUNT_DIR"
        ;;

    Darwin)
        IMG_FILE="$SCRIPT_DIR/log.dmg"
        if [[ -e "$IMG_FILE" ]]; then
            echo "Error: image already exists: $IMG_FILE. Run ./detach_disk.sh first." >&2
            exit 1
        fi

        hdiutil create -quiet -size "${SIZE_MB}m" -fs "Journaled HFS+" \
            -volname logs "$IMG_FILE"
        printf '%s\n%s\n' "$IMG_FILE" "" > "$STATE_FILE"

        $SUDO hdiutil attach -quiet -nobrowse -mountpoint "$MOUNT_DIR" "$IMG_FILE"
        $SUDO chown "$(id -u):$(id -g)" "$MOUNT_DIR"
        ;;

    FreeBSD)
        IMG_FILE="$SCRIPT_DIR/log.img"
        make_image "$IMG_FILE"

        DEV=$($SUDO mdconfig -a -t vnode -f "$IMG_FILE")
        printf '%s\n%s\n' "$IMG_FILE" "$DEV" > "$STATE_FILE"

        $SUDO newfs -U "/dev/$DEV" > /dev/null
        $SUDO mount "/dev/$DEV" "$MOUNT_DIR"
        $SUDO chown "$(id -u):$(id -g)" "$MOUNT_DIR"
        ;;
esac

echo "Disk mounted at $MOUNT_DIR (${SIZE_MB} MB)."
