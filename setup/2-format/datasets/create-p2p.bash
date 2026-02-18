#!/usr/bin/env bash
function helptext {
    echo "Usage: create-p2p.bash"
    echo
    echo 'This dataset is created on the OS pool because it has a lot of otherwise unused capacity + I/O and the NAS pool has dedicated its SSD mirror to metadata + small files + SLOG.'
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
DATASET_NAME="$ENV_POOL_NAME_OS/data/srv/p2p"
MOUNTPOINT='/srv/p2p'
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
