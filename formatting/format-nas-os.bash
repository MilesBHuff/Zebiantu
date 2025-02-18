#!/usr/bin/env bash
function helptext {
    echo "Usage: format-nas-os.bash 'device0 device1 [device2 ...]'"
    echo
    echo 'Pass at least two block devices as arguments.'
    echo 'All specified devices will be made into mirrors of each other, encrypted with LUKS, and formatted as btrfs.'
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
ENV_FILE='../env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source ../env.sh
else
    echo "ERROR: Missing '$ENV_FILE'."
    exit 2
fi
if [[
    -z "$ENV_SSD_SECTOR_SIZE" ||\
    -z "$ENV_OS_NAME" ||\
    -z "$ENV_OS_LUKS_NAME"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Format devices
set -e
mdadm --create --verbose --level=1 --raid-devices=$# --metadata=1.2 --name="$ENV_OS_NAME" "/dev/md/$ENV_OS_NAME" "$@"
cryptsetup luksFormat "/dev/md/$ENV_OS_NAME"
cryptsetup open "/dev/md/$ENV_OS_NAME" "$ENV_OS_LUKS_NAME"
mkfs.btrfs -L "${ENV_OS_NAME^^}" --sectorsize "$ENV_SSD_SECTOR_SIZE" -c lzo "/dev/mapper/$ENV_OS_LUKS_NAME"

## First mount
MOUNTPOINT="/tmp/mnt-$(uuidgen)"
mkdir -p "$MOUNTPOINT"
mount -o "${ENV_OS_MOUNT_OPTIONS:-defaults}" "/dev/md/$ENV_OS_NAME" "$MOUNTPOINT"
sleep 1
umount -f "$MOUNTPOINT"
rmdir "$MOUNTPOINT"

## Done
exit 0
