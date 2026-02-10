#!/bin/dash
## Idempotently tune system I/O.
set -u #NOTE: I don't think there's a need for `set -e` here.

#################
## PREPARATION ##
#################

## Make sure we're root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

## Try to load environment variables from some possible locations.
for ENV_FILE in \
    '/etc/filesystem-env.sh' \
    '../filesystem-env.sh'
do
    if [ -f "$ENV_FILE" ]; then
        . "$ENV_FILE"
        break
    fi
done

## Check to make sure that all required environment variables are defined.
for KEY in \
    ENV_NVME_QUEUE_DEPTH \
    ENV_POOL_NAME_DAS \
    ENV_POOL_NAME_NAS \
    ENV_POOL_NAME_OS \
    ENV_RECORDSIZE_HDD \
    ENV_RECORDSIZE_SSD
do
    eval "VALUE=\${$KEY}"
    if [ -z "$VALUE" ]; then
        echo "ERROR: Missing environment variable: $KEY" >&2
        exit 1
    fi
done

apply_setting() {
    VALUE=$1; unset 1
    KEYPATH=$2; unset 2
    [ -f "$KEYPATH" ] || return 1
    echo "'$VALUE' > '$KEYPATH'"
    echo "$VALUE" > "$KEYPATH"
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        echo "$0: failed to write \`$VALUE\` to '$KEYPATH'; value remains \`$(cat "$KEYPATH" 2>/dev/null)\`." >&2
        return $EXIT_CODE
    fi
}

#################
## DEVICE LOOP ##
#################

for DEV in /sys/block/sd* /sys/block/nvme*n*; do
    [ -e "$DEV" ] || continue

    DEV_BASENAME="$(basename "$DEV")"
    DEV_NODE="/dev/$DEV_BASENAME"

    ## Attempt to mark flash drives are non-rotational, accepting that there will be false negatives.
    if udevadm info --query=property --name="$DEV_NODE" 2>/dev/null | grep -q FLASH; then  #NOTE: This heuristic is imperfect, and depends upon the device not lying about being FLASH. To be fair, if rotational media advertises itself as "FLASH", it's not really our fault if we misidentify it here.
        SETTING_NEW=0
        SETTING_PATH="$DEV/queue/rotational"
        apply_setting "$SETTING_NEW" "$SETTING_PATH"
    fi
    ROTATIONAL=$(cat "$DEV/queue/rotational" 2>/dev/null || echo 1)

    ## If device is USB, detect BOT vs UAS
    IS_BOT=0
    DRIVER_PATH="$(readlink -f "$DEV/device/driver" 2>/dev/null || true)"
    case "$DRIVER_PATH" in */usb-storage) IS_BOT=1 ;; esac
    unset DRIVER_PATH

    ## Queue depth
    SETTING_NEW=32
    [ "$ROTATIONAL" -eq 1 ] && SETTING_NEW=16 ## Cap HDD queue depths (prevents head-thrashing / improves latency without harming throughput) (16 is what Exoses are rated for.)
    case "$DEV_BASENAME" in nvme*) SETTING_NEW=$ENV_NVME_QUEUE_DEPTH ;; esac #TODO: Set this dynamically to the NVMe's actual max queue depth.
    [ "$IS_BOT" -eq 1 ] && SETTING_NEW=1 ## BOT only supports 1.
    SETTING_PATH="$DEV/device/queue_depth"
    apply_setting "$SETTING_NEW" "$SETTING_PATH"

    ## Scheduler
    #NOTE: HDDs and BOT USBs need a scheduler since they will have queues below what ZFS can control, thanks to their above queue limits.
    SETTING_NEW="mq-deadline"
    [ "$ROTATIONAL" -eq 0 ] && [ "$IS_BOT" -eq 0 ] && SETTING_NEW="none"
    SETTING_PATH="$DEV/queue/scheduler"
    apply_setting "$SETTING_NEW" "$SETTING_PATH"

    ## Disable complex request merging for NVMe
    case "$DEV_BASENAME" in
        nvme*)
            SETTING_NEW=1 ## The difference between this and 2 (disabled) is almost nothing for the CPU. Default is 0, which uses a less-simple algorithm.
            SETTING_PATH="$DEV/queue/nomerge"
            apply_setting "$SETTING_NEW" "$SETTING_PATH"
            ;;
    esac

    ## Check whether device is part of a ZFS pool
    IS_PART_OF_POOL=0
    for POOL_NAME in \
        "$ENV_POOL_NAME_DAS" \
        "$ENV_POOL_NAME_NAS" \
        "$ENV_POOL_NAME_OS"
    do
        DEVICES=$(zpool status -P "$POOL_NAME" 2>/dev/null | awk '$1 ~ /^\// {print $1}')
        for DEVICE in $DEVICES; do #WARN: Does not support spaces in device paths, but this shouldn't ever be an issue.
            DISK=$(readlink -f "$DEVICE" 2>/dev/null | sed 's|^/dev/||')
            if [ "/sys/block/$DISK" = "$DEV" ]; then
                IS_PART_OF_POOL=1
                break
            fi
        done
        [ "$IS_PART_OF_POOL" -eq 1 ] && break
    done
    if [ "$IS_PART_OF_POOL" -eq 1 ]; then

        ## Match readahead size to the pool's recordsize
        #WARN: This code currently only works with recordsizes under 1M! (It expects "K".)
        REGEX='s/K$//'
        if [ "$ROTATIONAL" -eq 0 ]; then
            SETTING_NEW=$(echo "$ENV_RECORDSIZE_SSD" | sed "$REGEX")
        else
            SETTING_NEW=$(echo "$ENV_RECORDSIZE_HDD" | sed "$REGEX")
        fi
        unset REGEX

        SETTING_PATH="$DEV/queue/read_ahead_kb"
        apply_setting "$SETTING_NEW" "$SETTING_PATH"

        ## Match optimal I/O size to the pool's recordsize
        SETTING_PATH="$DEV/queue/optimal_io_size"
        if [ $(cat "$SETTING_PATH" 2>/dev/null || echo '-1')  -eq 0 ]; then ## Only set if accessible and the value indicates it wasn't already set.
            SETTING_NEW=$((SETTING_NEW * 1024))
            apply_setting "$SETTING_NEW" "$SETTING_PATH"
        fi
    fi
done

#############
## WRAP UP ##
#############

exit 0
