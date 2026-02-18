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

## Get input
declare -i YES_VM=-1
while true; do
    read -rp 'Will this OS run VMs? (y/n)' ANSWER
    case "$ANSWER" in
        y) YES_VM=1; break ;;
        n) YES_VM=0; break ;;
    esac
    unset ANSWER
done
declare -i YES_CONTAINER=-1
while true; do
    read -rp 'Will this OS run containers? (y/n)' ANSWER
    case "$ANSWER" in
        y) YES_CONTAINER=1; break ;;
        n) YES_CONTAINER=0; break ;;
    esac
    unset ANSWER
done

## Declare variables
#NOTE: All-caps is conventional for the dataset containing the OS, because capital letters sort before lowercase, and therefore load before lowercase.
declare -a DATASETS=()
declare -a   MOUNTS=()
## OS Datasets
DATASETS+=('/OS' '/OS/junk' '/OS/junk/cache'         '/OS/junk/coredump' '/OS/junk/crash' '/OS/junk/log' '/OS/junk/metrics' '/OS/junk/tmp')
MOUNTS+=(    '/'         ''     '/var/cache' '/var/lib/systemd/coredump'     '/var/crash'     '/var/log'     '/var/metrics'     '/var/tmp') #NOTE: `/tmp` and `/run` are tmpfs.
## User Datasets
DATASETS+=('/data' '/data/home' '/data/home/mail' '/data/home/root' '/data/srv')
MOUNTS+=(       ''      '/home'       '/var/mail'           '/root'      '/srv')
## Virtual Machine Datasets
if [[ $YES_VM -eq 1 ]]; then
    DATASETS+=('/data/vm' '/data/vm/img'    '/data/vm/img/libvirt' '/data/vm/raw')
    MOUNTS+=(          ''             '' '/var/lib/libvirt/images'             '')
fi
## Container Datasets
if [[ $YES_CONTAINER -eq 1 ]]; then
    DATASETS+=('/data/containers' '/data/containers/docker' '/data/containers/lxc' '/data/containers/podman')
    MOUNTS+=(                  ''         '/var/lib/docker'         '/var/lib/lxc'     '/var/lib/containers')
fi

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
zfs set com.sun:auto-snapshot=false "$ENV_POOL_NAME_OS/OS/junk"
# zfs set com.sun:auto-snapshot=false "$ENV_POOL_NAME_OS/data/containers" ## Not backed-up if not snapshotted.
zpool set bootfs="$ENV_POOL_NAME_OS/OS" "$ENV_POOL_NAME_OS"

## Ensure that `/etc/zfs/zpool.cache` exists and that everything is mounted.
if [[ ! -f '/etc/zfs/zpool.cache' ]]; then
    zpool export -f "$ENV_POOL_NAME_OS"
    zpool import -d /dev/disk/by-id -R "$ENV_ZFS_ROOT/$ENV_POOL_NAME_OS" -N "$ENV_POOL_NAME_OS"
    zfs load-key "$ENV_POOL_NAME_OS"
    zfs mount "$ENV_POOL_NAME_OS/OS"
    zfs mount "$ENV_POOL_NAME_OS/data/srv"
    zfs mount "$ENV_POOL_NAME_OS/data/home"
    zfs mount "$ENV_POOL_NAME_OS/data/home/mail"
    zfs mount "$ENV_POOL_NAME_OS/data/home/root"
fi

## Done
udevadm trigger
exit 0
