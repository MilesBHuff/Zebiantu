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
    -z "$ENV_NAME_OS" ||\
    -z "$ENV_NAME_OS_LUKS" ||\
    -z "$ENV_SECTOR_SIZE_SSD"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Format devices
set -e
mdadm --create --verbose --level=1 --raid-devices=$# --metadata=1.2 --name="$ENV_NAME_OS" "/dev/md/$ENV_NAME_OS" "$@"
cryptsetup luksFormat "/dev/md/$ENV_NAME_OS"
cryptsetup open "/dev/md/$ENV_NAME_OS" "$ENV_NAME_OS_LUKS"
mkfs.btrfs -L "${ENV_NAME_OS^^}" --sectorsize "$ENV_SECTOR_SIZE_SSD" -c lzo "/dev/mapper/$ENV_NAME_OS_LUKS"

## First mount
MOUNTPOINT="/tmp/mnt-$(uuidgen)"
mkdir -p "$MOUNTPOINT"
mount -o "${ENV_MOUNT_OPTIONS_OS:-defaults}" "/dev/md/$ENV_NAME_OS" "$MOUNTPOINT"
sleep 1
umount -f "$MOUNTPOINT"
rmdir "$MOUNTPOINT"

## Done
exit 0
