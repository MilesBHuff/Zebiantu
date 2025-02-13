#!/usr/bin/env bash
function helptext {
    echo 'Usage: partition-ssd-with-os.bash device0 [device1 ...]'
    echo
    echo 'Please pass as arguments all the block devices you wish to partition.'
    echo 'The provided block devices will all be given the same partition layout.'
    echo 'There will be an ESP partition, an OS partition, an SLOG partition, and an SVDEV partition.'
    echo
    echo 'Warning: This script does not check validity. Make sure your block devices exist and are the same size.'
}

## Validate parameters
if [[ $# -lt 1 ]]; then
    helptext >&2
    exit 1
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
    ## Create ESP partition
    sgdisk --new=1:2048:+500M --typecode=1:EF00 --change-name=1:ESP "$DEVICE"
    ## Create Linux OS partition
    sgdisk --new=2:0:+32G --typecode=2:8300 --change-name=2:OS "$DEVICE"
    ## Create SLOG partition
    sgdisk --new=3:0:+12G --typecode=3:BF02 --change-name=3:SLOG "$DEVICE"
    ## Create SVDEV partition
    sgdisk --new=4:0:0 --typecode=4:BF02 --change-name=4:SVDEV "$DEVICE"
done
exit $EXIT_CODE
