#!/usr/bin/env bash
function helptext {
    echo 'Usage: format-data-mirror.bash device0 [device1 ...]'
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

## Partition the disk
for DEVICE in "$@"; do
    if [[ ! -b "$DEVICE" ]]; then
        echo "ERROR: $DEVICE is not a valid block device." >&2
        continue
    fi
    ## Create GPT partition table
    sgdisk --zap-all "$DEVICE"
    ## Create SLOG partition
    sgdisk --new=1:0:+12G --typecode=1:BF01 --change-name=1:SLOG "$DEVICE"
    ## Create SVDEV partition
    sgdisk --new=2:0:0 --typecode=2:BF01 --change-name=2:SVDEV "$DEVICE"
done

## Done
exit 0
