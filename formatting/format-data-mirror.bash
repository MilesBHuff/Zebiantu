#!/usr/bin/env bash
function helptext {
    echo 'Usage: format-data-mirror.bash device0 device1 [device2 ...]'
    echo
    echo 'Please pass as arguments all the block devices you wish to include in the main data pool.'
    echo 'The provided block devices will be made into ZFS mirrors of each other.'
    echo
    echo 'You can configure this script by editing `env.sh`.'
    echo
    echo 'Warning: This script does not check validity. Make sure your block devices exist and are the same size.'
}

## Validate parameters
if [[ $# -lt 2 ]]; then
    helptext >&2
    exit 1
fi

## Define variables
ENV_FILE='./env.sh'; if [[ -f "$ENV_FILE" ]]; then source ./env.sh; else echo "ERROR: Missing '$ENV_FILE'."; exit -1; fi
ASHIFT=$(./helpers/calculate-powers-of-two.bash $ENV_HDD_SECTOR_SIZE)

## Create pool
set -e
zpool create \
    -o ashift="$ASHIFT" \
    -O recordsize=256K \
    -O special_small_blocks=64K \
    \
    -O sync=standard \
    -O logbias=latency \
    \
    -O atime=off \
    \
    -O xattr=sa \
    -O zilsaxattr=on \
    -O acltype=posixacl \
    -O aclinherit=passthrough \
    -O aclmode=passthrough \
    \
    -O redundant_metadata=most \
    \
    -O vdev_zaps_v2=on \
    \
    -O checksum=blake3 \
    \
    -O encryption=on \
    -O keyformat=passphrase \
    -O keylocation=prompt \
    \
    -O compression=zstd:3 \
    \
    "$ENV_POOL_NAME" \
    mirror "$@"
exit $?
