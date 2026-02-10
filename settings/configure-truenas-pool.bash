#!/usr/bin/env bash
## Configure TrueNAS's default pool's settings

## Make sure we're root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

## Get environment variables
ENV_FILE='../filesystem-env.sh'; if [[ -f "$ENV_FILE" ]]; then source "$ENV_FILE"; else echo "ERROR: Missing '$ENV_FILE'."; exit -1; fi
if [[ \
    -z "$ENV_SECONDS_DATA_LOSS_ACCEPTABLE" ||\
    -z "$ENV_SPEED_MBPS_MAX_SLOWEST_HDD" ||\
    -z "$ENV_THRESHOLD_SMALL_FILE" ||\
    -z "$ENV_ZPOOL_COMPRESSION_FREE"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Configure TrueNAS's boot pool
POOL_NAME='boot-pool'
zfs set atime=off "$POOL_NAME"
zfs set compression="$ENV_ZPOOL_COMPRESSION_FREE" "$POOL_NAME"
zfs set logbias=throughput "$POOL_NAME"
zfs set recordsize="$ENV_RECORDSIZE_SSD" "$POOL_NAME"
exit 0
