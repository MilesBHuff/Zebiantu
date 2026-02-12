#!/usr/bin/env bash

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
