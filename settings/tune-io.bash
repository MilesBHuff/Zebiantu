#!/bin/dash
## Idempotently tune system I/O.
set -u #NOTE: I don't think there's a need for `set -e` here.

#################
## PREPARATION ##
#################

## Make sure we're root
if [ "$(id -u)" -ne 0 ]; then
    echo "$0: This script must be run as root." >&2
    exit 1
fi

## Make sure we have an envfile in `/run` with all the variables we need — this script can run a lot, and it would be ideal for it to not cause recurring disk I/O when it does so.
ENV_CACHE='/run/tune-io.env'
if [ ! -f "$ENV_CACHE" ]; then

    LOCKDIR='/run/tune-io.lock'
    if ! mkdir "$LOCKDIR"; then

        ## Wait for the envfile cache to be generated.
        i=0
        while [ ! -f "$ENV_CACHE" ] && [ $i -lt 50 ]; do
            sleep 0.02
            i=$((i+1))
        done

        ## Clear out stale lockdirs.
        if [ -d "$LOCKDIR" ]; then
            NOW_EPOCH=$(date +%s)
            LOCK_EPOCH=$(stat -c %Y "$LOCKDIR" 2>/dev/null || echo $((NOW_EPOCH + 10)))
            [ $((NOW_EPOCH - LOCK_EPOCH)) -ge 10 ] && rmdir "$LOCKDIR" 2>/dev/null || true
        fi

        ## Exit if there's no envfile cache.
        if [ ! -f "$ENV_CACHE" ]; then
            echo "$0: Missing '$ENV_CACHE'." >&2
            exit 3
        fi
    else
        trap 'rmdir "$LOCKDIR"' EXIT HUP INT TERM

        ## Try to load environment variables from some possible locations.
        SUCCESS=0
        for ENV_FILE in \
            '/etc/filesystem-env.sh' \
            '../filesystem-env.sh'
        do
            if [ -f "$ENV_FILE" ]; then
                . "$ENV_FILE"
                SUCCESS=1
                break
            fi
        done
        if [ $SUCCESS -ne 1 ]; then
            echo "$0: Unable to find envfiles." >&2
            exit 1
        fi
        unset SUCCESS

        ## Create a randomly-named temporary file so that we don't conflict with concurrent runs of this script.
        SCRATCH_ENV_FILE=$(mktemp /run/tune-io.env.XXXXXX) || {
            echo "$0: Unable to create tempfile." >&2
            exit 4
        }
        chmod 0644 "$SCRATCH_ENV_FILE" || {
            echo "$0: Unable to chmod tempfile: '$SCRATCH_ENV_FILE'." >&2
            exit 5
        }

        ## Check to make sure that all required environment variables are defined; if they are, write them to the temporary envfile.
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
                echo "$0: Missing environment variable: '$KEY'." >&2
                rm -f "$SCRATCH_ENV_FILE"
                exit 2
            else
                echo "$KEY=$VALUE" >> "$SCRATCH_ENV_FILE"
            fi
        done

        ## Deploy the completed cache.
        mv -f "$SCRATCH_ENV_FILE" "$ENV_CACHE"
        unset SCRATCH_ENV_FILE

        ## Clean up
        rmdir "$LOCKDIR" && trap '' EXIT HUP INT TERM
    fi
fi

## Read environment from cache.
. "$ENV_CACHE"
KEYS=''
while IFS='=' read -r KEY VALUE; do
    # eval "$KEY=\$VALUE"
    KEYS="${KEYS:+$KEYS }$KEY"
done < "$ENV_CACHE"
export ${KEYS?}
unset KEYS ENV_CACHE

## Check interactivity
INTERACTIVE=0
case "$-" in *i*) INTERACTIVE=1 ;; esac

## This logs, performs, and handles attempts to change system settings.
apply_setting() {
    VALUE=$1
    KEYPATH=$2
    shift 2
    if [ ! -f "$KEYPATH" ]; then
        echo "$0: Missing path: '$KEYPATH'." >&2
        return 1
    fi
    ORIGINAL_VALUE="$(cat "$KEYPATH")"
    case "$ORIGINAL_VALUE" in
        *'['*']'*)
            PARSED_VALUE="$(echo "$ORIGINAL_VALUE" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')" #AI regex ## This works around values that print out a selection, like the I/O scheduler does.
            [ -n "$PARSED_VALUE" ] && ORIGINAL_VALUE="$PARSED_VALUE"
            unset PARSED_VALUE
            ;;
    esac
    if [ "$VALUE" = "$ORIGINAL_VALUE" ]; then
        [ $INTERACTIVE -eq 1 ] && echo "'$KEYPATH' = '$VALUE'"
        return 0
    else
        echo "'$KEYPATH' < '$VALUE'"
        echo "$VALUE" > "$KEYPATH"
        EXIT_CODE=$?
        [ $EXIT_CODE -ne 0 ] && echo "$0: Failed to write \`$VALUE\` to '$KEYPATH'; value remains \`$ORIGINAL_VALUE\`." >&2
        return $EXIT_CODE
    fi
}

## These are loop-invariants that are checked with each loop; I am caching them here to avoid unnecessary repeat calls.
#WARN: This code does not support spaces in device paths, but this shouldn't ever be an issue.
DISKS=''
while IFS='	' read -r _ VDEV _; do
    case "$VDEV" in
        /*)
            ## Map to device
            DEV="$(readlink -f "$VDEV" 2>/dev/null)" || continue
            DEV="${DEV#/dev/}"

            ## If partition, map to drive
            PARENT="$(lsblk -no PKNAME "/dev/$DEV" 2>/dev/null || true)"
            [ -n "$PARENT" ] && DEV="$PARENT"

            ## Append only if unique
            case " $DISKS " in
                *" $DEV "*) ;;
                *) DISKS="${DISKS:+$DISKS }$DEV" ;;
            esac
            ;;
    esac
done <<EOF
$(zpool list -v -H -P 2>/dev/null)
EOF

#################
## DEVICE LOOP ##
#################

for DEV in /sys/block/sd* /sys/block/nvme*n*; do
    [ -e "$DEV" ] || continue

    DEV_BASENAME="${DEV##*/}"
    DEV_NODE="/dev/$DEV_BASENAME"

    ## Attempt to mark flash drives are non-rotational, accepting that there will be false negatives.
    ROTATIONAL=$(cat "$DEV/queue/rotational" 2>/dev/null || echo 1)
    if [ $ROTATIONAL -eq 1 ]; then
        case "$(udevadm info --query=property --name="$DEV_NODE" 2>/dev/null)" in #TODO: Find a faster way to do this.
            *FLASH*) #NOTE: This heuristic is imperfect, and depends upon the device not lying about being FLASH. To be fair, if rotational media advertises itself as "FLASH", it's not really our fault if we misidentify it here.
                SETTING_NEW=0
                SETTING_PATH="$DEV/queue/rotational"
                apply_setting "$SETTING_NEW" "$SETTING_PATH"
                ROTATIONAL=$SETTING_NEW #NOTE: Not guaranteed to be true, but this is cheaper than doing a real check, and the rest of this script actually works better if it operates off the intended rotational status versus the actual.
                ;;
        esac
    fi

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
    for DISK in $DISKS; do
        if [ "/sys/block/$DISK" = "$DEV" ]; then
            IS_PART_OF_POOL=1
            break
        fi
    done
    if [ "$IS_PART_OF_POOL" -eq 1 ]; then

        ## Match readahead size to the pool's recordsize
        #WARN: This code currently only works with recordsizes under 1M! (It expects "K".)
        #WARN: This code currently does not get the pool's recordsize; it instead uses the environment variables that originally considered the pool's recordsize. #TODO: Use the real recordsize.
        if [ "$ROTATIONAL" -eq 0 ]; then
            SETTING_NEW="${ENV_RECORDSIZE_SSD%K}"
        else
            SETTING_NEW="${ENV_RECORDSIZE_HDD%K}"
        fi

        SETTING_PATH="$DEV/queue/read_ahead_kb"
        apply_setting "$SETTING_NEW" "$SETTING_PATH"

        ## Match optimal I/O size to the pool's recordsize
        SETTING_PATH="$DEV/queue/optimal_io_size"
        if IFS= read -r OIOS < "$SETTING_PATH" 2>/dev/null && [ "$OIOS" -eq 0 ]; then ## Only set if accessible and the value indicates it wasn't already set.
            SETTING_NEW=$((SETTING_NEW * 1024))
            apply_setting "$SETTING_NEW" "$SETTING_PATH"
        fi
    fi
done

#############
## WRAP UP ##
#############

exit 0
