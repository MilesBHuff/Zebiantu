#!/usr/bin/env bash
function helptext {
    echo "Usage: format-os.bash device0 [device1 ...]"
    echo
    echo 'Pass at least one block device as an argument.'
    echo 'If more than one device is specified, then all will be made into mirrors of each other.'
    echo
    echo 'You can configure this script by editing `env.sh`.'
    echo
    echo 'Warning: This script does not check validity. Make sure your block devices exist and are the same size.'
    echo 'Info: This script is written for putting the OS on an SSD.'
    echo 'Notice: You need to use systemd-boot and put /boot on your ESP, or you need to use ZFSBootMenu.'
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
    -z "$ENV_POOL_NAME_OS" ||\
    -z "$ENV_RECORDSIZE_SSD" ||\
    -z "$ENV_SECTOR_SIZE_OS" ||\
    -z "$ENV_ZPOOL_ATIME" ||\
    -z "$ENV_ZPOOL_CASESENSITIVITY" ||\
    -z "$ENV_ZPOOL_CHECKSUM" ||\
    -z "$ENV_ZPOOL_COMPRESSION_FREE" ||\
    -z "$ENV_ZPOOL_ENCRYPTION" ||\
    -z "$ENV_ZPOOL_NORMALIZATION"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Calculate ashift
ASHIFT_SCRIPT='./helpers/calculate-power-of-two.bash'
[[ -x "$ASHIFT_SCRIPT" ]] && ASHIFT=$("$ASHIFT_SCRIPT" $ENV_SECTOR_SIZE_OS)
declare -i ASHIFT=12 #FIXME: Workaround for script not firing. Not terrible to leave in here, though: although my current OS drives are 512Bn and can do ashift=9, future drives will probably not be 512Bn; doing ashift=12 now wastes a little space but avoids a resilver in the future.
if [[ -z $ASHIFT ]]; then
   echo "ERROR: Misconfigured sector sizes in '$ENV_FILE'." >&2
   exit 4
fi

## Create pool
set -e
zpool create -f \
    -o ashift="$ASHIFT" \
    -O recordsize="$ENV_RECORDSIZE_SSD" \
    \
    -O sync=standard \
    -O logbias=throughput \
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
    -O encryption="$ENV_ZPOOL_ENCRYPTION" \
    -O pbkdf2iters="$ENV_ZPOOL_PBKDF2ITERS" \
    -O keyformat=passphrase \
    -O keylocation="file:///etc/zfs/keys/$ENV_POOL_NAME_OS.key" \
    \
    -O compression="$ENV_ZPOOL_COMPRESSION_BEST" \
    \
    -O canmount=off \
    -O mountpoint=none \
    -R "$ENV_ZFS_ROOT/$ENV_POOL_NAME_OS" \
    \
    "$ENV_POOL_NAME_OS" \
    "$MIRROR" "$@"
    # -O checksum="$ENV_ZPOOL_CHECKSUM" \ ## Debian sucks and ships an ancient version of ZFS that doesn't support BLAKE3, and there is no canonical way to get ZFS 2.2 onto Bookworm. Shit distro.
echo 'Make sure to change compression from BEST to FAST after installation!'
echo "(zstd decompression times are essentially constant, so compressing extra during installation (when perf doesn't matter) is free savings.)"

## First import
zpool export "$ENV_POOL_NAME_OS"
zpool import -d /dev/disk/by-id "$ENV_POOL_NAME_OS"
zfs load-key "$ENV_POOL_NAME_OS"

## Create datasets
bash ./datasets/create-datasets-for-os.bash

## Done
zfs snapshot "${ENV_POOL_NAME_OS}@initial"
exit 0
