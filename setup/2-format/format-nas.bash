#!/usr/bin/env bash
function helptext {
    echo "Usage: format-nas.bash 'device0 device1 [device2 ...]' 'device0 device1 [device2 ...]' 'device0 device1 [device2 ...]' ['device0']"
    echo
    echo 'The first argument is a space-delimited list of block devices to use for the main storage pool.'
    echo 'The second argument is a space-delimited list of block devices to use for the special vdev.'
    echo 'The third argument is a space-delimited list of block devices to use for the SLOG.'
    echo 'The fourth argument is optional, and is a single block device to use for the L2ARC.'
    echo
    echo 'There must be at least two devices in each argument.'
    echo 'All same-argument devices will be mirrored.'
    echo
    echo 'You can configure this script by editing `env.sh`.'
    echo
    echo 'Warning: This script does not support spaces inside of device paths.'
    echo 'Warning: This script does not check validity. Make sure your block devices exist and are the same size.'
}

## Validate parameters
if [[ $# -lt 3 || $# -gt 4 ]]; then
    helptext >&2
    exit 1
fi

## Get environment
ENV_FILE='../../env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "ERROR: Missing '$ENV_FILE'." >&2
    exit 2
fi
if [[
    -z "$ENV_NAME_CACHE" ||\
    -z "$ENV_NAME_RESERVED" ||\
    -z "$ENV_NAME_VDEV" ||\
    -z "$ENV_POOL_NAME_NAS" ||\
    -z "$ENV_RECORDSIZE_HDD" ||\
    -z "$ENV_SECTOR_SIZE_HDD" ||\
    -z "$ENV_SECTOR_SIZE_SSD" ||\
    -z "$ENV_THRESHOLD_SMALL_FILE" ||\
    -z "$ENV_ZPOOL_ATIME" ||\
    -z "$ENV_ZPOOL_CASESENSITIVITY" ||\
    -z "$ENV_ZPOOL_CHECKSUM" ||\
    -z "$ENV_ZPOOL_COMPRESSION_FAST" ||\
    -z "$ENV_ZPOOL_ENCRYPTION" ||\
    -z "$ENV_ZPOOL_NORMALIZATION"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi
ZPOOL_REDUNDANT_METADATA='most'

## Calculate ashift
[[ $ENV_SECTOR_SIZE_SSD -gt $ENV_SECTOR_SIZE_HDD ]] && declare -i SECTOR_SIZE=$ENV_SECTOR_SIZE_SSD || SECTOR_SIZE=$ENV_SECTOR_SIZE_HDD
ASHIFT_SCRIPT='./helpers/calculate-power-of-two.bash'
[[ -x "$ASHIFT_SCRIPT" ]] && ASHIFT=$("$ASHIFT_SCRIPT" $SECTOR_SIZE)
if [[ -z $ASHIFT ]]; then
   echo "ERROR: Misconfigured sector sizes in '$ENV_FILE'." >&2
   exit 4
fi

## Are we adding an L2ARC?
[[ $# -eq 4 ]] && CACHE="cache $4"

echo ':: Unmounting and exporting old pool...'
zpool export -f "$ENV_POOL_NAME_NAS"

echo ':: Clearing out old filesystems...'
echo '(This is necessary to avoid issues on import later.)'
for DEVICE in $(echo $1 $2 $3 $4 | xargs); do
    zpool labelclear -f "$DEVICE"
    wipefs -a "$DEVICE"
done

echo ':: Creating the pool...'
set -e
zpool create -f \
    -o compatibility="$ENV_ZPOOL_COMPATIBILITY" \
    \
    -o ashift="$ASHIFT" \
    -O recordsize="$ENV_RECORDSIZE_HDD" \
    -O special_small_blocks="$ENV_THRESHOLD_SMALL_FILE" \
    \
    -O sync=standard \
    -O logbias=latency \
    \
    -O normalization="$ENV_ZPOOL_NORMALIZATION" \
    -O casesensitivity="$ENV_ZPOOL_CASESENSITIVITY" \
    \
    -O atime="$ENV_ZPOOL_ATIME" \
    \
    -O xattr=sa \
    -O acltype=posixacl \
    -O aclinherit=passthrough \
    -O aclmode=passthrough \
    \
    -O dnodesize=auto \
    -O redundant_metadata="$ZPOOL_REDUNDANT_METADATA" \
    \
    -O checksum="$ENV_ZPOOL_CHECKSUM" \
    \
    -O encryption="$ENV_ZPOOL_ENCRYPTION" \
    -O pbkdf2iters="$ENV_ZPOOL_PBKDF2ITERS" \
    -O keyformat=passphrase \
    -O keylocation="file:///etc/zfs/keys/$ENV_POOL_NAME_NAS.key" \
    \
    -O compression="$ENV_ZPOOL_COMPRESSION_FAST" \
    \
    -O canmount=on \
    -O mountpoint="$ENV_ZFS_ROOT/$ENV_POOL_NAME_NAS" \
    \
    "$ENV_POOL_NAME_NAS" \
    mirror $1 \
    special mirror $2 \
    log mirror $3 \
    $CACHE

echo ':: Importing...'
zpool export -f "$ENV_POOL_NAME_NAS"
zpool import -d /dev/disk/by-id "$ENV_POOL_NAME_NAS"
zfs load-key "$ENV_POOL_NAME_NAS"

echo ':: Adjusting partition metadata...'
sgdisk --typecode=1:bf02 "$4" ## Makes more sense for the cache device to use this code than the default.
sgdisk --change-name=1:"$ENV_NAME_CACHE" "$4" ## For consistency with the non-whole-disk partition labels.
sgdisk --change-name=9:"$ENV_NAME_RESERVED" "$4" ## Empty by default
for DEVICE in $1; do
    sgdisk --change-name=1:"$ENV_NAME_VDEV" "$DEVICE" ## For consistency with the non-whole-disk partition labels.
    sgdisk --change-name=9:"$ENV_NAME_RESERVED" "$DEVICE" ## Empty by default
done
partprobe

echo ':: Creating first snapshot...'
zfs snapshot "${ENV_POOL_NAME_NAS}@initial"

echo ':: Done.'
exit 0
