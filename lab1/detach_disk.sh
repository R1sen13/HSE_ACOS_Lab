#!/usr/bin/env bash
set -e -u -o pipefail

sudo umount logs
sudo losetup -d /dev/loop0
rm logs/log.img
rmdir logs