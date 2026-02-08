#!/usr/bin/env bash
function helptext {
    echo "Usage: format-das.bash device0 [device1 ...]"
    echo
    echo 'Pass at least one block device as an argument.'
    echo 'If more than one device is specified, then all will be made into mirrors of each other.'
    echo
    echo 'You can configure this script by editing `env.sh`.'
    echo
    echo 'Warning: This script does not check validity. Make sure your block devices exist and are the same size.'
}

## Validate parameters
if [[ $# -lt 1 ]]; then
    helptext >&2
    exit 1
fi

## Configure mirror-related settings
[[ $# -gt 1 ]] && MIRROR='mirror' && ZPOOL_REDUNDANT_METADATA='most' || ZPOOL_REDUNDANT_METADATA='all'

## Get environment
ENV_FILE='../../env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "ERROR: Missing '$ENV_FILE'." >&2
    exit 2
fi
if [[
    -z "$ENV_POOL_NAME_DAS" ||\
    -z "$ENV_RECORDSIZE_HDD" ||\
    -z "$ENV_SECTOR_SIZE_HDD" ||\
    -z "$ENV_SECTOR_SIZE_SSD" ||\
    -z "$ENV_ZPOOL_ATIME" ||\
    -z "$ENV_ZPOOL_CASESENSITIVITY" ||\
    -z "$ENV_ZPOOL_CHECKSUM" ||\
    -z "$ENV_ZPOOL_COMPRESSION_MOST" ||\
    -z "$ENV_ZPOOL_ENCRYPTION" ||\
    -z "$ENV_ZPOOL_NORMALIZATION"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Calculate ashift
[[ $ENV_SECTOR_SIZE_SSD -gt $ENV_SECTOR_SIZE_HDD ]] && declare -i SECTOR_SIZE=$ENV_SECTOR_SIZE_SSD || SECTOR_SIZE=$ENV_SECTOR_SIZE_HDD
ASHIFT_SCRIPT='./helpers/calculate-power-of-two.bash'
[[ -x "$ASHIFT_SCRIPT" ]] && ASHIFT=$("$ASHIFT_SCRIPT" $SECTOR_SIZE)
if [[ -z $ASHIFT ]]; then
   echo "ERROR: Misconfigured sector sizes in '$ENV_FILE'." >&2
   exit 4
fi

echo ':: Unmounting and exporting old pool...'
zpool export -f "$ENV_POOL_NAME_DAS"

echo ':: Clearing out old filesystems...'
echo '(This is necessary to avoid issues on import later.)'
for DEVICE in "$@"; do
    zpool labelclear -f "$DEVICE"
    wipefs -a "$DEVICE"
done

echo ':: Creating the pool...'
set -e
zpool create -f \
    -o ashift="$ASHIFT" \
    -O recordsize="$ENV_RECORDSIZE_HDD" \
    \
    -O sync=disabled \
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
    -O keylocation="file:///etc/zfs/keys/$ENV_POOL_NAME_DAS.key" \
    \
    -O compression="$ENV_ZPOOL_COMPRESSION_MOST" \
    \
    -O canmount=on \
    -O mountpoint="$ENV_ZFS_ROOT/$ENV_POOL_NAME_DAS" \
    \
    "$ENV_POOL_NAME_DAS" \
    $MIRROR "$@"

echo ':: Importing...'
zpool export -f "$ENV_POOL_NAME_DAS"
zpool import -d /dev/disk/by-id "$ENV_POOL_NAME_DAS"
zfs load-key "$ENV_POOL_NAME_DAS"
zfs mount "$ENV_POOL_NAME_DAS"

echo ':: Adjusting partition metadata...'
for DEVICE in "$@"; do
    sgdisk --change-name=1:"$ENV_NAME_VDEV" "$DEVICE" ## For consistency with the non-whole-disk partition labels.
    sgdisk --change-name=9:"$ENV_NAME_RESERVED" "$DEVICE" ## Empty by default
done
partprobe

echo ':: Creating first snapshot...'
zfs snapshot "${ENV_POOL_NAME_DAS}@initial"

echo ':: Done.'
exit 0
