#!/usr/bin/env bash
function helptext {
    echo "Usage: create-os.bash"
    echo
    echo 'Warning: This script does not check validity — make sure your pool exists.'
}

## Get environment
ENV_FILE='../../../filesystem-env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "ERROR: Missing '$ENV_FILE'."
    exit 2
fi
if [[
    -z "$ENV_POOL_NAME_OS" ||\
    -z "$ENV_SNAPSHOT_NAME_INITIAL" ||\
    -z "$ENV_ZFS_ROOT"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Declare variables
#NOTE: All-caps is conventional for the dataset containing the OS, because capital letters sort before lowercase, and therefore load before lowercase.
declare -a DATASETS=('/data' '/data/home' '/data/home/root' '/data/srv' '/data/var'  '/OS' '/OS/debian') ## The idea is to allow for separate OS snapshots and data snapshots while excluding unimportant tempfiles. The few things in `/var` that need to be kept with rollbacks can be placed into `/varkeep` and symlinked/bind-mounted back to their original locations.
declare -a   MOUNTS=(     ''      '/home'           '/root'      '/srv'      '/var'     ''          '/')

if [[ ! ${#DATASETS[@]} -eq ${#MOUNTS[@]} ]]; then
    echo "ERROR: Mismatch in number of items in the DATASETS (${#DATASETS[@]}) and MOUNTS (${#MOUNTS[@]}) arrays; please fix!" >&2
    exit 3
fi
declare -i COUNT=${#DATASETS[@]}

## Create datasets
set -e
declare -i I=0
while [[ $I -lt $COUNT ]]; do
    if [[ "${MOUNTS[$I]}" == '' ]]; then
        zfs create \
            \
            -o canmount=off \
            -o mountpoint=none \
            \
            "$ENV_POOL_NAME_OS${DATASETS[$I]}"
    else
        zfs create \
            \
            -o canmount=$([[ ${MOUNTS[$I]} == '/' ]] && echo noauto || echo on) \
            -o mountpoint="${MOUNTS[$I]}" \
            \
            "$ENV_POOL_NAME_OS${DATASETS[$I]}"
    fi
    zfs snapshot "$ENV_POOL_NAME_OS${DATASETS[$I]}@$ENV_SNAPSHOT_NAME_INITIAL"
    ((++I))
done
set +e

## Configure datasets
zfs set com.sun:auto-snapshot=false "$ENV_POOL_NAME_OS/data/var"
zpool set bootfs="$ENV_POOL_NAME_OS/OS/linux" "$ENV_POOL_NAME_OS"

## Ensure that `/etc/zfs/zpool.cache` exists and that everything is mounted.
if [[ ! -f '/etc/zfs/zpool.cache' ]]; then
    zpool export -f "$ENV_POOL_NAME_OS"
    zpool import -d /dev/disk/by-id -R "$ENV_ZFS_ROOT/$ENV_POOL_NAME_OS" -N "$ENV_POOL_NAME_OS"
    zfs load-key "$ENV_POOL_NAME_OS"
    zfs mount "$ENV_POOL_NAME_OS/OS/linux"
    zfs mount "$ENV_POOL_NAME_OS/data/var"
    zfs mount "$ENV_POOL_NAME_OS/data/srv"
    zfs mount "$ENV_POOL_NAME_OS/data/home"
    zfs mount "$ENV_POOL_NAME_OS/data/home/root"
fi

## Done
udevadm trigger
exit 0
