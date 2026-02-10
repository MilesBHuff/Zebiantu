#!/usr/bin/env bash
function helptext {
    echo 'Usage: partition-data.bash device0 [device1 ...]'
    echo
    echo 'Please pass as arguments all the block devices you wish to partition.'
    echo 'The provided block devices will all be given the same partition layout.'
    echo 'There will be an SLOG partition and an SVDEV partition.'
    echo
    echo 'You can configure this script by editing `filesystem-env.sh`.'
    echo
    echo 'Warning: This script does not check validity. Make sure your block devices exist and are the same size.'
}

## Validate parameters
if [[ $# -lt 1 ]]; then
    helptext >&2
    exit 1
fi

## Get environment
ENV_FILE='../../filesystem-env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "ERROR: Missing '$ENV_FILE'."
    exit 2
fi
if [[
    -z "$ENV_NAME_RESERVED" ||\
    -z "$ENV_NAME_SLOG" ||\
    -z "$ENV_NAME_SVDEV" ||\
    -z "$ENV_ZFS_SECTORS_RESERVED"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Validate the passed devices
declare -i EXIT_CODE=0
for DEVICE in "$@"; do
    if [[ ! -b "$DEVICE" ]]; then
        echo "ERROR: $DEVICE is not a valid block device." >&2
        EXIT_CODE=2
        continue
    fi
done
set -e

## Clear the devices
echo ':: Preparing devices for partitioning...'
for DEVICE in "$@"; do
    ## TRIM entire device (also wipes data, albeit insecurely)
    blkdiscard -f "$DEVICE" &
    ## Create GPT partition table
    sgdisk --zap-all "$DEVICE" &
done
wait
echo ':: Done!'
echo

## Partition the devices
for DEVICE in "$@"; do
    echo ":: Partitioning '$DEVICE'..."

    ## Ensure correct alignment value.
    declare -i ALIGNMENT=$(((1024 ** 2) / $(blockdev --getss "$DEVICE"))) ## Always equals 1MiB in sectors. Is 2048 unless drive is 4Kn, in which case is 256. This math avoids the undesirable default situation which is to waste 8MiB instead of 1MiB on 4Kn disks.
    echo "'$ALIGNMENT': This should be 2048 (logical sector size == 512B) or 256 (4Kn). If it's neither of those, investigate."

    echo ':: Creating padding partition...'
    echo 'This partition sits at the end of the drive, and helps you to resilver with drives of slightly different sizes.'
    echo 'This partition is equal to 8MiB, and is not aligned to drive sectors. Creating it will throw warnings about alignment; ignore them.'
    sgdisk --set-alignment=1 --new=9:-"$ENV_ZFS_SECTORS_RESERVED":0 --typecode=9:BF07 --change-name=9:"$ENV_NAME_RESERVED" "$DEVICE"

    echo ':: Creating SLOG partition...'
    sgdisk --set-alignment=$ALIGNMENT --new=1:0:+12GiB --typecode=1:BF02 --change-name=1:"$ENV_NAME_SLOG" "$DEVICE"

    echo ':: Creating SVDEV partition...'
    sgdisk --set-alignment=$ALIGNMENT --new=2:0:0 --typecode=2:BF01 --change-name=2:"$ENV_NAME_SVDEV" "$DEVICE"

    echo ":: Done with '$DEVICE'."
    echo
done
exit $EXIT_CODE
