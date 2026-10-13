#!/usr/bin/env bash
set -e -u -o pipefail

mkdir -p logs
dd if=/dev/zero of=logs/log.img bs=1M count=2048 status=progress
LOOP=$(sudo losetup -fP --show logs/log.img)
sudo mkfs.ext4 /dev/loop0
sudo mount /dev/loop0 logs
