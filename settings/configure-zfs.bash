#!/usr/bin/env bash
## Configure ZFS kernel settings

## Make sure we're root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

## Get environment variables
ENV_FILE='../env.sh'; if [[ -f "$ENV_FILE" ]]; then source ../env.sh; else echo "ERROR: Missing '$ENV_FILE'."; exit -1; fi
if [[ \
    -z "$ENV_ACCEPTABLE_DATA_LOSS_SECONDS" ||\
    -z "$ENV_SLOWEST_HDD_MAX_SPEED_MBPS" ||\
    -z "$ENV_SMALL_FILE_THRESHOLD"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Recreate the config file that this script manages.
FILE='/etc/modprobe.d/zfs-customized.conf'
: > "$FILE"
chmod 644 "$FILE"

## Write ZFS configurations to the file.
echo "options zfs l2arc_write_max=$(($ENV_SLOWEST_SSD_MAX_SPEED_MBPS / 2))" >> "$FILE"
echo "options zfs l2arc_write_boost=$(($ENV_THEORETICAL_MAX_SSD_SPEED_MBPS - ($ENV_SLOWEST_SSD_MAX_SPEED_MBPS / 2)))" >> "$FILE"
##
echo "options zfs zfs_immediate_write_sz=$((${ENV_SMALL_FILE_THRESHOLD#K} * 1024))" >> "$FILE"
##
echo "options zfs zfs_txg_timeout=$ENV_ACCEPTABLE_DATA_LOSS_SECONDS" >> "$FILE"
echo "options zfs zfs_dirty_data_max=$(($ENV_ACCEPTABLE_DATA_LOSS_SECONDS * ($ENV_SLOWEST_HDD_AVG_SPEED_MBPS * (1024**2))))" >> "$FILE" ## Sanity check: Default is 4294967296 (4G)
echo "options zfs zfs_dirty_data_max_max=$(($ENV_ACCEPTABLE_DATA_LOSS_SECONDS * ($ENV_THEORETICAL_MAX_HDD_SPEED_MBPS * (1024**2))))" >> "$FILE" ## Sanity check: Default is 4294967296 (4G)
##
echo "options zfs zfs_prefetch_disable=0" >> "$FILE"
echo "options zfs l2arc_noprefetch=0" >> "$FILE"

## Notify user and exit.
echo "Please reboot for these settings to take effect."
exit 0
