#!/usr/bin/env bash
function helptext {
    echo "Usage: zfs-format-das-drives.bash device0 [device1 ...]"
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
[[ $# -gt 1 ]] && MIRROR='mirror'

## Get environment
ENV_FILE='../env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source ../env.sh
else
    echo "ERROR: Missing '$ENV_FILE'." >&2
    exit 2
fi
if [[
    -z "$ENV_HDD_SECTOR_SIZE" ||\
    -z "$ENV_SSD_SECTOR_SIZE" ||\
    -z "$ENV_DAS_POOL_NAME" ||\
    -z "$ENV_HDD_RECORDSIZE"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Calculate ashift
[[ $ENV_SSD_SECTOR_SIZE -gt $ENV_HDD_SECTOR_SIZE ]] && SECTOR_SIZE=$ENV_SSD_SECTOR_SIZE || SECTOR_SIZE=$ENV_HDD_SECTOR_SIZE
ASHIFT_SCRIPT='./helpers/calculate-powers-of-two.bash'
[[ -x "$ASHIFT_SCRIPT" ]] && ASHIFT=$("$ASHIFT_SCRIPT" $SECTOR_SIZE)
if [[ -z $ASHIFT ]]; then
   echo "ERROR: Misconfigured sector sizes in '$ENV_FILE'." >&2
   exit 4
fi

## Create pool
set -e
zpool create \
    -o ashift="$ASHIFT" \
    -O recordsize="$ENV_HDD_RECORDSIZE" \
    \
    -O sync=disabled \
    -O logbias=latency \
    \
    -O normalization=formD \
    -O casesensitivity=sensitive \
    \
    -O atime=off \
    \
    -O xattr=sa \
    -O acltype=posixacl \
    -O aclinherit=passthrough \
    -O aclmode=passthrough \
    \
    -O dnodesize=auto \
    -O redundant_metadata=most \
    \
    -O checksum=blake3 \
    \
    -O encryption=aes-256-gcm \
    -O keyformat=passphrase \
    -O keylocation=prompt \
    \
    -O compression=lz4 \
    \
    -O canmount=on \
    -O mountpoint="$ENV_ZFS_ROOT/$ENV_DAS_POOL_NAME" \
    \
    "$ENV_DAS_POOL_NAME" \
    "$MIRROR" "$@"
exit $?
