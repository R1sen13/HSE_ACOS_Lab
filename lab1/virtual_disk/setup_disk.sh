#!/usr/bin/env bash
set -e -u -o pipefail

SIZE_MB=${1:-2048}

USER_NAME=$(id -u -n)
GROUP_NAME=$(id -g -n)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"

LOG_DIR="$PROJECT_DIR/logs"
IMAGE_PATH="$LOG_DIR/log.img"

mkdir -p "$LOG_DIR"

dd if=/dev/zero of="$IMAGE_PATH" bs=1M count="$SIZE_MB" status=progress

LOOP_DEV=$(sudo losetup -fP --show "$IMAGE_PATH")
sudo mkfs.ext4 "$LOOP_DEV"
sudo mount "$LOOP_DEV" "$LOG_DIR"
sudo chown "${USER_NAME}:${GROUP_NAME}" "$LOG_DIR"
