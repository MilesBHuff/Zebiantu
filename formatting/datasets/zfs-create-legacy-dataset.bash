#!/usr/bin/env bash
function helptext {
    echo "Usage: zfs-create-legacy-dataset.bash pool-name"
    echo
    echo 'Pass the name of the pool where you want to create this dataset.'
    echo
    echo 'This dataset is for storing data brought in from disparate other backup sources.'
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
DATASET_NAME='legacy'

## Get environment
ENV_FILE='../env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source ../env.sh
else
    echo "ERROR: Missing '$ENV_FILE'."
    exit 2
fi
if [[
    -z "$ENV_ZFS_ROOT"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Create dataset
set -e
zfs create \
    \
    -o utf8only=off \
    -o normalization=none \
    \
    -o canmount=on \
    -o mountpoint="$ENV_ZFS_ROOT/$1/$DATASET_NAME" \
    \
    "$1/$DATASET_NAME"
exit $?
