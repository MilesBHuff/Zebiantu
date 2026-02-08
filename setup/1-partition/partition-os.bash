#!/usr/bin/env bash
function helptext {
    echo 'Usage: partition-os.bash device0 [device1 ...]'
    echo
    echo 'Please pass as arguments all the block devices you wish to partition.'
    echo 'The provided block devices will all be given the same partition layout.'
    echo 'There will be an ESP partition and an OS partition.'
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
ENV_FILE='../../env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "ERROR: Missing '$ENV_FILE'."
    exit 2
fi
if [[
    -z "$ENV_NAME_ESP" ||\
    -z "$ENV_NAME_OS" ||\
    -z "$ENV_NAME_RESERVED" ||\
    -z "$ENV_NAME_SLOG" ||\
    -z "$ENV_NAME_SVDEV" ||\
    -z "$ENV_ZFS_SECTORS_RESERVED"
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
    ## Ensure correct alignment value.
    declare -i ALIGNMENT=$(((1024 ** 2) / $(blockdev --getss "$DEVICE"))) ## Always equals 1MiB in sectors. Is 2048 unless drive is 4Kn, in which case is 256. This math avoids the undesirable default situation which is to waste 8MiB instead of 1MiB on 4Kn disks.
    ## TRIM entire device (also wipes data, albeit insecurely)
    # blkdiscard -f "$DEVICE"
    ## Create GPT partition table
    set +e
    sgdisk --zap-all "$DEVICE" >/dev/null 2>&1 ## First run seems to always fail on this one; maybe some kind of issue with mdadm?
    set -e
    sgdisk --zap-all "$DEVICE"
    ## Create reserved partition (to allow for future drive size mismatches)
    sgdisk --set-alignment=1 --new=9:-"$ENV_ZFS_SECTORS_RESERVED":0 --typecode=9:BF07 --change-name=9:"$ENV_NAME_RESERVED" "$DEVICE"
    ## Create ESP
    sgdisk --set-alignment=$ALIGNMENT --new=1:0:+261MiB --typecode=1:EF00 --change-name=1:"${ENV_NAME_ESP^^}" "$DEVICE" ## Microsoft has good reasons for using 260MiB for its own ESPs: 260MiB is the bare minimum that FAT32 can be with 4K sectors. We then add an extra 1MiB to that to fit the 128KiB from mdadm.
    ## Create ZFS Partition
    sgdisk --set-alignment=$ALIGNMENT --new=2:0:0 --typecode=2:BF00 --change-name=2:"${ENV_NAME_OS^^}" "$DEVICE"
done
exit $EXIT_CODE
