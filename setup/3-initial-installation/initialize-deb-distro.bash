#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob
function helptext {
    echo "Usage: install-deb-distro.bash"
    echo
    echo 'This script installs Debian or Ubuntu to the target directory.'
    echo "It assumes you are running it from a LiveCD for either Debian ($DEBIAN_VERSION) or Ubuntu Server ($UBUNTU_VERSION)."
    echo 'It also assumes that you are connected to the Internet.'
}
## Special thanks to https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Bookworm%20Root%20on%20ZFS.html
## Special thanks to ChatGPT for helping with my endless questions.

###############################
##   B O I L E R P L A T E   ##
###############################
echo ':: Initializing...'

## Base paths
CWD=$(pwd)
ROOT_DIR="$CWD/../.."

## Import functions
declare -a HELPERS=('../helpers/load_envfile.bash' '../helpers/idempotent_append.bash')
for HELPER in "${HELPERS[@]}"; do
    if [[ -x "$HELPER" ]]; then
        source "$HELPER"
    else
        echo "ERROR: Failed to load '$HELPER'." >&2
        exit 1
    fi
done

###########################
##   V A R I A B L E S   ##
###########################

echo ':: Getting the environment...'
## Load and validate environment variables
load_envfile "$ROOT_DIR/filesystem-env.sh" \
    ENV_NAME_ESP \
    ENV_POOL_NAME_OS \
    ENV_ZFS_ROOT
load_envfile "$ROOT_DIR/setup-env.sh" \
    ENV_SETUP_ENVFILE \
    DEBIAN_VERSION \
    UBUNTU_VERSION

echo ':: Setting the target...'
## Validate and set our sights on the directory which will contain the new operating system
export TARGET="$ENV_ZFS_ROOT/$ENV_POOL_NAME_OS"
if ! mountpoint -q "$TARGET"; then
    echo "ERROR: Target '$TARGET' not mounted!" >&2
    exit 4
fi
cd "$TARGET"

echo ':: Determining distro...'
## Get current distro
declare -i DISTRO=0
while [[ "$DISTRO" -ne 1 && "$DISTRO" -ne 2 ]]; do
    set +e
    read -rp "Which distro are we setting up? (Type '1' for 'Debian' or '2' for 'Ubuntu') " DISTRO
    set -e
done
export DISTRO

##########################
##   B O O T S T R A P  ##
##########################

## Install base system
echo ':: Installing base system...'
apt update
apt install -y debootstrap
if [[ $DISTRO -eq 1 ]]
    then debootstrap "$DEBIAN_VERSION" "$TARGET"
    else debootstrap "$UBUNTU_VERSION" "$TARGET" 'https://archive.ubuntu.com/ubuntu'
fi

## Replicate certain core files from the host system
echo ':: Seeding the configuration...'
install -d  -m 755 '/etc/zfs'                         "$TARGET/etc/zfs"
install     -m 644 '/etc/zfs/zpool.cache'             "$TARGET/etc/zfs/zpool.cache"
install -d  -m 700 '/etc/zfs/keys'                    "$TARGET/etc/zfs/keys"
for KEYFILE in '/etc/zfs/keys/'*; do
    install -m 600 "$KEYFILE"                         "$TARGET/etc/zfs/keys/"
done
install     -m 644 '/etc/hostid'                      "$TARGET/etc/hostid" ## ZFS keeps track of the host that imported it in its cachefile, so we need to keep the same hostid as the LiveCD.
install -D  -m 755 "$ROOT_DIR/filesystem-env.sh"      "$TARGET$ENV_FILESYSTEM_ENVFILE"; export ENV_FILESYSTEM_ENVFILE
install -D  -m 755 "$ROOT_DIR/setup-env.sh"           "$TARGET$ENV_SETUP_ENVFILE";      export ENV_SETUP_ENVFILE
install -D  -m 755 "$ROOT_DIR/settings/tune-io.dash"  "$TARGET$ENV_TUNE_IO_SCRIPT";     export ENV_TUNE_IO_SCRIPT
install -D  -m 755 "$ROOT_DIR/settings/tune-zfs.bash" "$TARGET$ENV_TUNE_ZFS_SCRIPT";    export ENV_TUNE_ZFS_SCRIPT

#####################
##   C H R O O T   ##
#####################

## Ensure that we umount on exit.
echo ':: Preparing for mounts...'
function cleanup {
    set -e
    cd "$TARGET"
    set +e
    umount -R dev proc run sys tmp media/scripts 2>/dev/null || true
}; trap cleanup EXIT

## Mount tmpfs dirs
echo ':: Mounting guest directories...'
declare -a TMPS=(tmp)
for TMP in "${TMPS[@]}"; do
    if mountpoint -q "$TMP"; then
        echo "WARN: '$TMP' is already mounted." >&2
    else
        mkdir -p "$TMP"
        mount -t tmpfs -o nosuid,nodev,mode=1777 tmpfs "$TMP"
    fi
done

## Bind-mount system directories for chroot
echo ':: Bind-mounting host directories...'
declare -a BIND_DIRS=(dev proc run sys)
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
echo ':: Done.'
echo 'You will now be dropped into a chroot of your new system.'
echo "Please run the following script: /$SCRIPTS_DIR/helpers/install-deb-distro-from-chroot.bash"
exec chroot "$TARGET" env bash --login
