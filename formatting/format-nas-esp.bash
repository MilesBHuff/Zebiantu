#!/usr/bin/env bash
function helptext {
    echo "Usage: format-nas-esp.bash 'device0 device1 [device2 ...]'"
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
ENV_FILE='./env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source ./env.sh
else
    echo "ERROR: Missing '$ENV_FILE'."
    exit 2
fi
if [[
    -z "$ENV_SSD_SECTOR_SIZE" ||\
    -z "$ESP_NAME"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Format devices
set -e
mdadm --create --verbose --level=1 --raid-devices=$# --metadata=1.0 --name="$ESP_NAME" "/dev/md/$ESP_NAME" "$@"
mkfs.vfat -F 32 -S "$ENV_SSD_SECTOR_SIZE" -s 1 -h 0 -n "$ESP_NAME" "/dev/md/$ESP_NAME" #NOTE: For 8K-native disks, pass: `-S 4096 -s 2`.

## First mount
MOUNTPOINT="/tmp/mnt-$(uuidgen)"
mkdir -p "$MOUNTPOINT"
mount -o "${ESP_MOUNT_OPTIONS:-defaults}" "/dev/md/$ESP_NAME" "$MOUNTPOINT"
sleep 1
umount -f "$MOUNTPOINT"
rmdir "$MOUNTPOINT"

## Done
exit 0
