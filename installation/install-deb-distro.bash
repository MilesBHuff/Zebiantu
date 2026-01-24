#!/usr/bin/env bash
function helptext {
    echo "Usage: install-deb-distro.bash"
    echo
    echo 'This script installs Debian to the target directory.'
    echo "It assumes you are running it from a LiveCD for either Debian ($DEBIAN_VERSION) or Ubuntu Server ($UBUNTU_VERSION)."
    echo 'It also assumes that you are connected to the Internet.'
}
## Special thanks to https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Bookworm%20Root%20on%20ZFS.html
## My thanks to ChatGPT (not as the author of this code (that's me), but for helping with my endless questions and providing advice)
set -euo pipefail

## Get environment
ENV_FILE='../env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
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
export UBUNTU_VERSION='noble' #TODO: Change once Resolute Racoon (26.04) comes out.
export DEBIAN_VERSION='trixie'

## Mount tmpfs dirs
echo ':: Mounting tmpfs dirs...'
declare -a TMPS=(run tmp)
for TMP in "${TMPS[@]}"; do
    if mountpoint -q "$TMP"; then
        echo "WARN: '$TMP' is already mounted." >&2
    else
        mkdir -p "$TMP"
        mount -t tmpfs tmpfs "$TMP"
    fi
done

## Do the do
echo ':: Debootstrapping...'
declare -i DISTRO=0
while [[ "$DISTRO" != '1' && "$DISTRO" != '2' ]]; do
    set +e
    read -p "Which distro are we setting up? (Type '1' for 'Debian' or '2' for 'Ubuntu') " DISTRO
    set -e
done
export DISTRO
apt install -y debootstrap
if [[ $DISTRO -eq 1 ]]
    then debootstrap "$DEBIAN_VERSION" "$TARGET"
    else debootstrap "$UBUNTU_VERSION" "$TARGET" 'http://archive.ubuntu.com/ubuntu'
fi
## Bring over thinks from /etc
echo ':: Bringing over configs...'
declare -a FILES=('etc/zfs/zpool.cache' "etc/zfs/keys/$ENV_POOL_NAME_OS.key")
for FILE in "${FILES[@]}"; do
    mkdir -p "$(dirname -- "$FILE")"
    [[ -e "/$FILE" ]] && cp "/$FILE" "$FILE" || echo "WARN: '/$FILE' does not exist!" >&2
done
unset FILES
cp /etc/hostid etc/hostid ## ZFS keeps track of the host that imported it in its cachefile, so we need to keep the same hostid as the LiveCD.

## Bind-mount system directories for chroot
echo ':: Bindmounting directories for chroot...'
declare -a BIND_DIRS=(dev proc sys)
for BIND_DIR in "${BIND_DIRS[@]}"; do
    if mountpoint -q "$BIND_DIR"; then
        echo "WARN: '$BIND_DIR' is already mounted." >&2
    else
        mkdir -p "$BIND_DIR"
        mount --make-private --rbind "/$BIND_DIR" "$BIND_DIR"
    fi
done
SCRIPTS_DIR='media/scripts'
if mountpoint -q "$SCRIPTS_DIR"; then
    echo "WARN: '$SCRIPTS_DIR' is already mounted." >&2
else
    mkdir -p "$SCRIPTS_DIR"
    mount --bind "$CWD" "$SCRIPTS_DIR"
fi

## Run chroot-based scripts
echo ':: Run the following script in chroot:'
echo ":: /$SCRIPTS_DIR/helpers/install-deb-distro-from-chroot.bash"
exec chroot "$TARGET" env bash --login
