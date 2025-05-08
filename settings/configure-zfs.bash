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
    -z "$ENV_SECONDS_DATA_LOSS_ACCEPTABLE" ||\
    -z "$ENV_SPEED_MBPS_MAX_SLOWEST_HDD" ||\
    -z "$ENV_THRESHOLD_SMALL_FILE"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Recreate the config file that this script manages.
FILE='/etc/modprobe.d/zfs-customized.conf'
: > "$FILE"
chmod 644 "$FILE"

## Write ZFS configurations to the file.
echo "options zfs l2arc_write_max=$(($ENV_SPEED_MBPS_MAX_SLOWEST_SSD / 2))" >> "$FILE"
echo "options zfs l2arc_write_boost=$(($ENV_SPEED_MBPS_MAX_THEORETICAL_SSD - ($ENV_SPEED_MBPS_MAX_SLOWEST_SSD / 2)))" >> "$FILE"
##
echo "options zfs zfs_immediate_write_sz=$((${ENV_THRESHOLD_SMALL_FILE#K} * 1024))" >> "$FILE"
##
echo "options zfs zfs_txg_timeout=$ENV_SECONDS_DATA_LOSS_ACCEPTABLE" >> "$FILE"
echo "options zfs zfs_dirty_data_max=$(($ENV_SECONDS_DATA_LOSS_ACCEPTABLE * ($ENV_SPEED_MBPS_AVG_SLOWEST_HDD * (1024**2))))" >> "$FILE" ## Sanity check: Default is 4294967296 (4G)
echo "options zfs zfs_dirty_data_max_max=$(($ENV_SECONDS_DATA_LOSS_ACCEPTABLE * ($ENV_SPEED_MBPS_MAX_THEORETICAL_HDD * (1024**2))))" >> "$FILE" ## Sanity check: Default is 4294967296 (4G)
##
echo "options zfs zfs_prefetch_disable=0" >> "$FILE"
echo "options zfs l2arc_noprefetch=0" >> "$FILE"

## Notify user and exit.
echo "Please reboot for these settings to take effect."
exit 0
