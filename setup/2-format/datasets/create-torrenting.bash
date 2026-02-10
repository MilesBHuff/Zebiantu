#!/usr/bin/env bash
function helptext {
    echo "Usage: create-torrenting.bash"
    echo
    echo 'It is created on the OS pool, as it the NAS pool has dedicated its SSD mirror to metadata+small files, and as the OS pool has a lot of otherwise unused capacity and I/O.'
    echo
    echo 'Warning: This script does not check validity — make sure your pool exists.'
}

## Get environment
ENV_FILE='../../../filesystem-env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "ERROR: Missing '$ENV_FILE'."
    exit 2
fi
if [[
    -z "$ENV_POOL_NAME_OS" ||\
    -z "$ENV_SNAPSHOT_NAME_INITIAL" ||\
    -z "$ENV_ZFS_ROOT"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Create dataset
DATASET_NAME="$ENV_POOL_NAME_OS/torrents"
MOUNTPOINT='/mnt/torrents'
zfs create \
    \
    -o canmount=on \
    -o mountpoint="$MOUNTPOINT" \
    \
    "$DATASET_NAME"

## Configure datasets
zfs set com.sun:auto-snapshot=false "$DATASET_NAME"

## Test mounting
mkdir -p "$MOUNTPOINT"
zfs mount "$MOUNTPOINT"

## Done
zfs snapshot "$DATASET_NAME@$ENV_SNAPSHOT_NAME_INITIAL"
exit 0
