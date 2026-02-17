#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## Make sure we are able to access certain non-ZFS filesystems
echo ':: Installing additional filesystems...'
declare -a FILESYSTEMS=(
    dosfstools ## Used by ESP
    exfatprogs ## Used by flashdrives
    f2fs-tools ## Used by flashdrives
    xfsprogs   ## Used by zvols
)
apt install -y "${FILESYSTEMS[@]}"
unset FILESYSTEMS
