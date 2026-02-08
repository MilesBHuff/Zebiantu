#!/usr/bin/env bash
function helptext {
    echo "Usage: create-recovered.bash pool-name"
    echo
    echo 'Pass the name of the pool where you want to create this dataset.'
    echo
    echo 'This dataset is for storing data recovered from damaged filesystems.'
    echo 'Data in this dataset should eventually be organized into other datasets.'
    echo
    echo 'Warning: This script does not check validity — make sure your pool exists.'
}

## Validate parameters
if [[ ! $# -eq 1 ]]; then
    helptext >&2
    exit 1
fi

## Variables
DATASET_NAME='legacy/recovered'

## Get environment
ENV_FILE='../../../env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "ERROR: Missing '$ENV_FILE'."
    exit 2
fi
if [[
    -z "$ENV_SNAPSHOT_NAME_INITIAL" ||\
    -z "$ENV_ZFS_ROOT" ||\
    -z "$ENV_ZPOOL_COMPRESSION_MOST"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Create dataset
set -e
zfs create \
    \
    -o normalization="$ENV_ZPOOL_NORMALIZATION" \
    \
    -o recordsize="$ENV_RECORDSIZE_ARCHIVE" \
    -o compression="$ENV_ZPOOL_COMPRESSION_MOST" \
    \
    -o canmount=on \
    -o mountpoint="$ENV_ZFS_ROOT/$1/$DATASET_NAME" \
    \
    "$1/$DATASET_NAME"

## Done
zfs snapshot "$1/$DATASET_NAME@$ENV_SNAPSHOT_NAME_INITIAL"
exit 0
