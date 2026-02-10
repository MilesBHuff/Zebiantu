#!/usr/bin/env bash
#IMPORTANT: It is imperative that the first snapshot on each dataset is the same exact name. If this is not the case, you will be in pain forever.

## Make sure we're root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

## Get environment variables
ENV_FILE='../filesystem-env.sh'; if [[ -f "$ENV_FILE" ]]; then source "$ENV_FILE"; else echo "ERROR: Missing '$ENV_FILE'."; exit -1; fi
if [[ \
    -z "$ENV_POOL_NAME_DAS" ||\
    -z "$ENV_POOL_NAME_NAS" ||\
    -z "$ENV_ZFS_ROOT"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Variables
[[ ! -z "$1" ]] && SRC_DS="$1" || SRC_DS="$ENV_POOL_NAME_NAS"
[[ ! -z "$2" ]] && OUT_DS_PARENT="$2" || OUT_DS_PARENT="$ENV_POOL_NAME_DAS"
OUT_DS="$OUT_DS_PARENT/$SRC_DS"
## "DS" -> "Dataset"
## "SRC" -> "Source"
## "OUT" -> "Output"

## Configurables
declare -i HOW_TO_REPLICATE=1 ## 0: First replication ever | 1: Subsequent replications | 2: Subsequent replications if `syncoid` is unavailable
[[ ! -z "$3" ]] && SNAPSHOT_NEW="$SRC_DS@$3" || SNAPSHOT_NEW= ## Only used in replication option 2. Optional.
[[ ! -z "$4" ]] && SNAPSHOT_OLD="$SRC_DS@$4" || SNAPSHOT_OLD= ## Only used in replication option 2. Find the last common snapshot with `zfs list -t snapshot`.

## Before a replication:
## * Unmount the target (it won't let you replicate otherwise)
## * Allow writes to the target
if zfs list -Ho name "$OUT_DS"; then
    zfs umount "$OUT_DS"
    zfs set readonly=off "$OUT_DS"
    zfs list -Hro name "$OUT_DS" | while read -r DS; do
        zfs set mountpoint=none "$DS"
    done
fi

set -e
case "$HOW_TO_REPLICATE" in
    0) ## Do this only for the first replication.
        SNAPSHOT="$SRC_DS@initial" ## Ideally, you should have created this snapshot when you first created the dataset, before any data was added.
        # zfs snapshot -r "$SNAPSHOT"
        zfs send -Rw "$SNAPSHOT" | zfs receive -F "$OUT_DS"
        ;;
    1) ## Do this on subsequent replications.
        syncoid --force --no-stream --sendoptions="-Iw" "$SRC_DS" "$OUT_DS" --recursive
        # syncoid --force --no-stream --sendoptions="-RIw" "$SRC_DS" "$OUT_DS" ## Only works if all children have identical snapshots
        ;;
    2) ## Do this on subsequent replications only if syncoid isn't available.
        if [[ -z "$SNAPSHOT_NEW" ]]; then
            SNAPSHOT="$SRC_DS@$(date --iso-8601=seconds | sed 's/+00:00$//' | sed 's/:/-/g' | sed 's/T/_/')"
            zfs snapshot -r "$SNAPSHOT"
        else
            SNAPSHOT="$SNAPSHOT_NEW"
        fi
        zfs send -i "$SNAPSHOT_OLD" -Rw "$SNAPSHOT" | zfs receive -F "$OUT_DS"
        unset SNAPSHOT SNAPSHOT_NEW SNAPSHOT_OLD
        ;;
esac

## Unlock the replicated dataset
zfs load-key -r "$OUT_DS"

## After a replication
zfs list -Hro name "$OUT_DS" | while read -r DS; do
    MOUNTPOINT="$ENV_ZFS_ROOT/$OUT_DS_PARENT${DS#$OUT_DS_PARENT}"
    zfs set mountpoint="$MOUNTPOINT" "$DS"
done
zfs set readonly=on "$OUT_DS"

## Mount the replicated dataset
zfs mount -a

## Done
exit 0
