#!/usr/bin/env bash
## Configure ZFS kernel settings

#################
## PREPARATION ##
#################

## Make sure we're root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

## Get environment variables
ENV_FILE='../env.sh'; if [[ -f "$ENV_FILE" ]]; then source "$ENV_FILE"; else echo "ERROR: Missing '$ENV_FILE'."; exit 2; fi
if [[ \
    -z "$ENV_DEVICES_IN_L2ARC" ||\
    -z "$ENV_ENDURANCE_L2ARC" ||\
    -z "$ENV_MTBF_TARGET_L2ARC" ||\
    -z "$ENV_RECORDSIZE_HDD" ||\
    -z "$ENV_RECORDSIZE_SSD" ||\
    -z "$ENV_SECONDS_DATA_LOSS_ACCEPTABLE" ||\
    -z "$ENV_SPEED_L2ARC" ||\
    -z "$ENV_SPEED_MBPS_MAX_SLOWEST_HDD" ||\
    -z "$ENV_THRESHOLD_SMALL_FILE"
]]; then #TODO: Add missing used variables above!
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Recreate the config file that this script manages.
FILE='/etc/modprobe.d/zfs-customized.conf'
: > "$FILE"
chmod 644 "$FILE"

#################
## QUEUE DEPTH ##
#################
## The ZFS settings here affect all devices, including NVMes; but I'm using my NVMes for L2ARC, which ZFS heavily rate-limits for longevity, so it shouldn't matter that we're limiting them to a SATA queue depth.
## The defaults set tight per-pipe minima/maxima; I manage to accomplish the same ends with greater flexibility for lopsided loads by setting an overall limit, lower per-pipe minima, and larger per-pipe maxima.
## To avoid bad settings, I have ensured that symmetrical load totals match those of the defaults. In order to do this, it was necessary to first understand ZFS's scheduler's algorithm.
## Algorithm: (All loops go in order from sync_read to sync_write to async_read to async_write to scrub.) First, loop through and assign one command to each category until all minima are filled. Then, repeat until all maxima are filled or the total queue limit is hit.

## Max queue depth (32 is the max supported by SATA)
echo "options zfs             zfs_vdev_max_active=32" >> "$FILE" #DEFAULT: 1000 (basically uncapped)

## Min queue depths per category (I can't fault most of these, but the sync categories are much higher than they need to be to accomplish the same end per the algorithm used.)
echo "options zfs   zfs_vdev_sync_read_min_active=5"  >> "$FILE" #DEFAULT:   10
echo "options zfs  zfs_vdev_sync_write_min_active=5"  >> "$FILE" #DEFAULT:   10
echo "options zfs  zfs_vdev_async_read_min_active=2"  >> "$FILE" #DEFAULT:    2
echo "options zfs zfs_vdev_async_write_min_active=1"  >> "$FILE" #DEFAULT:    1
echo "options zfs       zfs_vdev_scrub_min_active=1"  >> "$FILE" #DEFAULT:    1
##                                               =14             #DEFAULT:  =24

## Max queue depths per category
## The highest sensible value for any of these is probably the CPU core count (in my case, 24 after SMT), or the max queue depth (32), whichever is lower, because any higher would put multiple of the same kind of I/O thread on the same core, which is counterproductive, or because there would be more items to queue than the queue is large.
## However, 24 is so high as to be meaningless in most contexts (and should be viewed as being effectively uncapped). For the first three categories, that's actually okay; but for the last two categories, having high maxima results in them being given far too much weight. Async writes and scrubs have zero impact on applications, so they should not be allowed more resources than absolutely necessary. Their defaults are reasonable and battle-hardened.
echo "options zfs   zfs_vdev_sync_read_max_active=24" >> "$FILE" #DEFAULT:   10
echo "options zfs  zfs_vdev_sync_write_max_active=24" >> "$FILE" #DEFAULT:   10
echo "options zfs  zfs_vdev_async_read_max_active=24" >> "$FILE" #DEFAULT:   10
echo "options zfs zfs_vdev_async_write_max_active=3"  >> "$FILE" #DEFAULT:    3
echo "options zfs       zfs_vdev_scrub_max_active=2"  >> "$FILE" #DEFAULT:    2
##                                               =77             #DEFAULT:  =35
## Yes, the total is supposed to be higher than (or equal to) the hard max (32 in my case).

#RESULT: values under symmetrical load: 32,10,10,7,3,2 (matches default of 32;10,10,7,3,2)

function apply-setting {
    [[ ! -f "$2" ]] && return 1
    COMMAND="echo '$1' > '$2'"
    echo "$COMMAND"
    eval "$COMMAND"
    [[ ! $? = 0 ]] && echo "$0: current value: $(cat "$2")" >&2
}

#TODO: Make persistent via udev, so that it will automatically re-apply whenever devices are inserted/removed.
#FIXME: Linux assumes rotational by default, which results in flashdrives incorrectly being marked as rotational.
for DEV in /sys/block/sd* /sys/block/nvme*n*; do
    ROTATIONAL=$(cat "$DEV/queue/rotational")

    ## Configure queue depth limits per-device
    SETTING_NEW=32
    [[ $ROTATIONAL -eq 1 ]] && SETTING_NEW=16 ## Cap HDD queue depths (prevents head-thrashing / improves latency without harming throughput) (16 is what Exoses are rated for.)
    SETTING_PATH="$DEV/device/queue_depth"
    apply-setting "$SETTING_NEW" "$SETTING_PATH"

    ## Configure schedulers per-device
    #NOTE: HDDs need a scheduler since they will have queues below what ZFS can control, thanks to their queue cap.
    SETTING_NEW='mq-deadline'
    [[ $ROTATIONAL -eq 0 ]] && SETTING_NEW='none'
    SETTING_PATH="$DEV/queue/scheduler"
    apply-setting "$SETTING_NEW" "$SETTING_PATH"

    ## Disable complex request merging for NVMe
    if [[ "$DEV" == *nvme* ]]; then
        SETTING_NEW=1 ## Difference between this and 2 (disabled) is almost nothing for the CPU. Default is 0, which uses a less-simple algorithm.
        SETTING_PATH="$DEV/queue/nomerge"
        apply-setting "$SETTING_NEW" "$SETTING_PATH"
    fi

    ## Should match recordsize on disks in ZFS pool
    if true; then #TODO: Limit to only ZFS disks

        #WARN: This code only works with recordsizes under 1M! (It expects "K".)
        SETTING_NEW="${ENV_RECORDSIZE_HDD%K}" ## Default: 128
        [[ $ROTATIONAL -eq 0 ]] && SETTING_NEW="${ENV_RECORDSIZE_SSD%K}"
        SETTING_PATH="$DEV/queue/read_ahead_kb"
        apply-setting "$SETTING_NEW" "$SETTING_PATH"

        SETTING_PATH="$DEV/queue/optimal_io_size"
        if [[ $(cat "$SETTING_PATH") -eq 0 ]]; then ## Only set if it wasn't set automatically.
            SETTING_NEW=$((SETTING_NEW * 1024))
            apply-setting "$SETTING_NEW" "$SETTING_PATH"
        fi
    fi
done

#################################
## MISCELLANEOUS CONFIGURATION ##
#################################

## Avoid contention between the SVDEV and the SLOG, which share a device and a sync domain.
echo "options zfs zfs_immediate_write_sz=$((${ENV_THRESHOLD_SMALL_FILE%K} * 1024))" >> "$FILE"
## TXG Tuning
echo "options zfs zfs_txg_timeout=$ENV_SECONDS_DATA_LOSS_ACCEPTABLE" >> "$FILE"
#echo "options zfs zfs_dirty_data_max=$(($ENV_SECONDS_DATA_LOSS_ACCEPTABLE * ($ENV_SPEED_MBPS_MAX_SLOWEST_HDD * (1024**2))))" >> "$FILE" ## Sanity check: Default is 4294967296 (4GiB) #NOTE: This is already auto-tuned every few seconds to accomplish the same goal.
#echo "options zfs zfs_dirty_data_max_max=$(($ENV_SECONDS_DATA_LOSS_ACCEPTABLE * ($ENV_SPEED_MBPS_MAX_THEORETICAL_HDD * (1024**2))))" >> "$FILE" ## Sanity check: Default is 4294967296 (4GiB) ## This is necessary to avoid a situation where you have more in your TXGs than your drives can physically eat in your timeout. There is no reason to allow this. #NOTE: This can only be configured at module load.
## L2ARC Throttling
echo "options zfs l2arc_write_max=$((ENV_DEVICES_IN_L2ARC * ((ENV_ENDURANCE_L2ARC * (1024**4)) / (ENV_MTBF_TARGET_L2ARC * (3652425 / 10000) * 24 * 60 * 60))))" >> "$FILE" ## Sets the L2ARC feed rate to the value that kills the L2ARC device at the appointed time. The default is 8M; this sets it to 2M on a consumer NVMe or 87M on an enterprise one.
echo "options zfs l2arc_write_boost=$((ENV_DEVICES_IN_L2ARC * ((ENV_SPEED_L2ARC * (1024**2)) / 2)))" >> "$FILE" ## Sets the temporary fill rate of L2ARC to half its speed.
## Limits (no direct effects)
echo "options zfs zfs_max_recordsize=$((16 * (1024**2)))" >> "$FILE" ## Allows setting 16M recordsizes

#############
## WRAP UP ##
#############

## Load written configurations
while read -r LINE; do
    COMMAND=$(echo "$LINE" | sed 's/^options zfs \+/\/sys\/module\/zfs\/parameters\//' | sed 's/^\(.*\)=\(.*\)$/echo \2 > \1/')
    echo "$COMMAND"
    eval "$COMMAND"
done < "$FILE"
#NOTE: `zfs_dirty_data_max_max` cannot be set at runtime, but rather only at module load.

## All done!
exit 0
