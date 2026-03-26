#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## Install and configure ZFS
echo ':: Installing ZFS...'
case $DISTRO in
    1) apt install -y -t "$DEBIAN_VERSION-backports" zfsutils-linux zfs-zed zfs-dkms ;;
    2) apt install -y zfsutils-linux zfs-zed ;;
esac
ZFS_VERSION="$(zfs --version | head -n1 | cut -c5-)"
dpkg --compare-versions "$ZFS_VERSION" lt 2.2 && idempotent_append 'REMAKE_INITRD=yes' '/etc/dkms/zfs.conf' ## Needed on ZFS < 2.2, deprecated on ZFS >= 2.2
unset ZFS_VERSION
systemctl enable zfs-zed
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE zfs_force=0" ## Apparently, some implementations default this to `1`, which has been known to cause corruption. (https://github.com/openzfs/zfs/issues/12842#issuecomment-1328943097)

## Enable automatic mounting during boot
systemctl enable zfs.target
systemctl enable zfs-import.target
systemctl enable zfs-mount

## Preserve the live environment's memory of the root pool.
echo ':: Configuring the cache of ZFS devices...'
mkdir -p '/etc/zfs/zfs-list.cache'
touch "/etc/zfs/zfs-list.cache/$ENV_POOL_NAME_SYS"
# zed -F
TARGET_ESCAPED=$(printf '%s\n' "$TARGET" | sed 's/[\/&]/\\&/g') #AI
[[ -n "$TARGET_ESCAPED" ]] || exit 99
sed -Ei "s|$TARGET_ESCAPED/?|/|" '/etc/zfs/zfs-list.cache/'*
unset TARGET_ESCAPED
systemctl enable zfs-import-cache

## Set up ZFS in the initramfs
echo ':: Configuring the initramfs to support ZFS...'
case $DISTRO in
    1) apt install -y -t "$DEBIAN_VERSION-backports" zfs-initramfs ;;
    2) apt install -y zfs-initramfs ;;
esac
KEYDIR=/etc/zfs/keys
install -m 700 -d "$KEYDIR"
KEYFILE="$KEYDIR/$ENV_POOL_NAME_SYS.key"
if [[ ! -f "$KEYFILE" ]]; then
    install -m 600 '/dev/null' "$KEYFILE"
    read -rp "A file is about to open; enter your ZFS encryption password into it. This is necessary to prevent double-prompting during boot. Press 'Enter' to continue. " _; unset _
    nano "$KEYFILE"
fi
zfs set keylocation=file://"$KEYFILE" "$ENV_POOL_NAME_SYS"
echo 'UMASK=0077' > /etc/initramfs-tools/conf.d/umask.conf
echo "FILES=\"$KEYDIR/*\"" > /etc/initramfs-tools/conf.d/99-zfs-keys.conf
unset KEYDIR KEYFILE
