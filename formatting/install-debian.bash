#!/usr/bin/env bash
function helptext {
    echo "Usage: install-debian.bash"
    echo
    echo 'This script installs Debian to the target directory.'
    echo 'It assumes you are running it from a Debian LiveCD that is connected to the Internet.'
}
## Special thanks to https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Bookworm%20Root%20on%20ZFS.html
## Also thanks to ChatGPT (not for code, but for helping with some installataion steps)
set -euo pipefail

## Get environment
ENV_FILE='../env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source ../env.sh
else
    echo "ERROR: Missing '$ENV_FILE'." >&2
    exit 2
fi
if [[
    -z "$ENV_NAME_ESP" ||\
    -z "$ENV_POOL_NAME_OS" ||\
    -z "$ENV_ZFS_ROOT"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi

## Set variables
echo ':: Setting variables...'
export TARGET="$ENV_ZFS_ROOT/$ENV_POOL_NAME_OS"
if [[ ! -d "$TARGET" ]]; then
    echo "ERROR: Target '$TARGET' not mounted!" >&2
    exit 4
fi
CWD=$(pwd)
cd "$TARGET"

## Mount tmpfs dirs
echo ':: Mounting tmpfs dirs...'
declare -a TMPS=(run tmp)
for TMP in "${TMPS[@]}"; do
    mkdir "$TMP"
    mount -t tmpfs tmpfs "$TMP"
done

## Do the do
echo ':: Debootstrapping...'
apt install -y debootstrap
debootstrap bookworm "$TARGET"

## Bring over ZFS imports
echo ':: Bringing over ZFS imports...'
mkdir -p etc/zfs/keys
declare -a ZFILES=('etc/zfs/zpool.cache' "etc/zfs/keys/$ENV_POOL_NAME_OS.key")
for ZFILE in "${ZFILES[@]}"; do
    [[ -e "/$ZFILE" ]] && cp "/$ZFILE" "$ZFILE" || echo "WARN: '/$ZFILE' does not exist!" >&2
done
unset ZFILES
cp /etc/hostid etc/hostid ## ZFS keeps track of the host that imported it in its cachefile, so we need to keep the same hostid as the LiveCD.

## Bind-mount system directories for chroot
echo ':: Bindmounting directories for chroot...'
declare -a BIND_DIRS=(dev proc sys)
for BIND_DIR in "${BIND_DIRS[@]}"; do
    mkdir -p "$BIND_DIR"
    mount --make-private --rbind "/$BIND_DIR" "$BIND_DIR"
done
SCRIPTS_DIR='media/scripts'
mkdir -p "$SCRIPTS_DIR"
mount --bind "$CWD" media/scripts

## Run chroot-based scripts
echo ':: Run the following script in chroot:'
echo ":: /$SCRIPTS_DIR/helpers/install-debian-from-chroot.bash"
exec chroot "$TARGET" env bash --login
