#!/usr/bin/env bash
function helptext {
    echo "Usage: format-esp.bash 'device0 device1 [device2 ...]'"
    echo
    echo 'Pass at least two block devices as arguments.'
    echo 'All specified devices will be made into mirrors of each other and formatted as EFI System Partitions.'
    echo
    echo 'You can configure this script by editing `env.sh`.'
    echo
    echo 'Warning: This script does not check validity. Make sure your block devices exist and are the same size.'
}

## Validate parameters
if [[ $# -lt 2 ]]; then
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
    -z "$ENV_SECTOR_SIZE_OS"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Format devices
set -e
MDNAME="$ENV_POOL_NAME_OS:$ENV_NAME_ESP" #NOTE: Must specify a hostname with a colon or it will autoinsert one.
mdadm --create --verbose --level=1 --raid-devices=$# --metadata=1.0 --name="$MDNAME" "/dev/md/$ENV_NAME_ESP" "$@"
mkfs.vfat -F 32 -f 2 -S "$ENV_SECTOR_SIZE_OS" -s 1 -h 0 -n "${ENV_NAME_ESP^^}" "/dev/md/$ENV_NAME_ESP" #NOTE: For 8K-native disks, pass: `-S 4096 -s 2`.

## First mount
MOUNTPOINT="/tmp/mnt-$(uuidgen)"
mkdir -p "$MOUNTPOINT"
mount -o "${ENV_MOUNT_OPTIONS_ESP:-defaults}" "/dev/md/$ENV_NAME_ESP" "$MOUNTPOINT"
sleep 1
umount -f "$MOUNTPOINT"
rmdir "$MOUNTPOINT"

## Done
exit 0
