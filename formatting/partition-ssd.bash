#!/usr/bin/env bash
function helptext {
    echo 'Usage: partition-ssd.bash device0 [device1 ...]'
    echo
    echo 'Please pass as arguments all the block devices you wish to partition.'
    echo 'The provided block devices will all be given the same partition layout.'
    echo 'There will be an SLOG partition and an SVDEV partition.'
    echo
    echo 'You can configure this script by editing `env.sh`.'
    echo
    echo 'Warning: This script does not check validity. Make sure your block devices exist and are the same size.'
}

## Validate parameters
if [[ $# -lt 1 ]]; then
    helptext >&2
    exit 1
fi

## Get environment
ENV_FILE='./env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source ./env.sh
else
    echo "ERROR: Missing '$ENV_FILE'."
    exit 2
fi
if [[
    -z "$SLOG_NAME" ||\
    -z "$SVDEV_NAME"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Partition the disk
set -e
declare -i EXIT_CODE=0
for DEVICE in "$@"; do
    if [[ ! -b "$DEVICE" ]]; then
        echo "ERROR: $DEVICE is not a valid block device." >&2
        EXIT_CODE=2
        continue
    fi
    ## Create GPT partition table
    sgdisk --zap-all "$DEVICE"
    ## Create SLOG partition
    sgdisk --new=1:0:+12G --typecode=1:BF02 --change-name=1:"$SLOG_NAME" "$DEVICE"
    ## Create SVDEV partition
    sgdisk --new=2:0:0 --typecode=2:BF02 --change-name=2:"$SVDEV_NAME" "$DEVICE"
done
exit $EXIT_CODE
