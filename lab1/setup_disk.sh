#!/usr/bin/env bash
set -e -u -o pipefail

SIZE_MB=${1:-2048}

USER_NAME=$(id -u -n)
GROUP_NAME=$(id -g -n)

mkdir -p logs

dd if=/dev/zero of=logs/log.img bs=1M count="${SIZE_MB}" status=progress

LOOP_DEV=$(sudo losetup -fP --show logs/log.img)
sudo mkfs.ext4 "${LOOP_DEV}"
sudo mount "${LOOP_DEV}" logs
sudo chown "${USER_NAME}:${GROUP_NAME}" logs
