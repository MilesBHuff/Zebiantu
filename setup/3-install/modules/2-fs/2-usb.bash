#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## Make sure we are able to access flashdrives
echo ':: Installing flashdrive filesystems...'
declare -a FILESYSTEMS=(
    exfatprogs ## Used by flashdrives
    f2fs-tools ## Used by flashdrives
)
apt install -y "${FILESYSTEMS[@]}"
unset FILESYSTEMS
