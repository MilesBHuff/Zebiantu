#!/usr/bin/env bash
set -e

## Make sure we're root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

## Get environment variables
ENV_FILE='../env.sh'; if [[ -f "$ENV_FILE" ]]; then source ../env.sh; else echo "ERROR: Missing '$ENV_FILE'."; exit -1; fi
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

## Before a replication
zfs unmount -a
zfs list -H -o name -r "$OUT_DS" | while read -r DS; do
    zfs set mountpoint=none "$DS"
done
zfs set readonly=off "$OUT_DS"

case "$HOW_TO_REPLICATE" in
    0) ## Do this only for the first replication.
        SNAPSHOT="$SRC_DS@initial"
        zfs snapshot -r "$SNAPSHOT"
        zfs send -Rw "$SNAPSHOT" | zfs receive -F "$OUT_DS"
        unset SNAPSHOT
        ;;
    1) ## Do this on subsequent replications.
        syncoid --force --no-stream --sendoptions="-Rw" "$SRC_DS" "$OUT_DS" # --recursive
        ;;
    2) ## Do this on subsequent replications only if syncoid isn't available.
        if [[ -z "$SNAPSHOT_NEW" ]]; then
            SNAPSHOT="$SRC_DS@$(date --iso-8601=seconds)"
            zfs snapshot -r "$SNAPSHOT"
        else
            SNAPSHOT="$SNAPSHOT_NEW"
        fi
        zfs send -i "$SNAPSHOT_OLD" -Rw "$SNAPSHOT" | zfs receive -F "$OUT_DS"
        unset SNAPSHOT SNAPSHOT_NEW SNAPSHOT_OLD
        ;;
esac

## After a replication
zfs list -H -o name -r "$OUT_DS" | while read -r DS; do
    MOUNTPOINT="$ENV_ZFS_ROOT/$OUT_DS_PARENT${DS#$OUT_DS_PARENT}"
    zfs set mountpoint="$MOUNTPOINT" "$DS"
    zfs set readonly=on "$DS"
done

## Unlock the replicated dataset
zfs load-key -r "$OUT_DS"
zfs mount -a

## Done
exit 0
