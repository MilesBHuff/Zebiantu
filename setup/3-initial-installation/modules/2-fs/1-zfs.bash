#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## Install and configure ZFS
echo ':: Installing ZFS...'
case $DISTRO in
    1) apt install -y -t "$DEBIAN_VERSION-backports" zfsutils-linux zfs-zed zfs-dkms ;;
    2) apt install -y -t "$UBUNTU_VERSION-backports" zfsutils-linux zfs-zed ;;
esac
ZFS_VERSION="$(zfs --version | head -n1 | cut -c5-)"
dpkg --compare-versions "$ZFS_VERSION" lt 2.2 && idempotent_append 'REMAKE_INITRD=yes' '/etc/dkms/zfs.conf' ## Needed on ZFS < 2.2, deprecated on ZFS >= 2.2
unset ZFS_VERSION
mkdir -p '/etc/zfs/zfs-list.cache'
touch "/etc/zfs/zfs-list.cache/$ENV_POOL_NAME_OS"
# zed -F
TARGET_ESCAPED=$(printf '%s\n' "$TARGET" | sed 's/[\/&]/\\&/g') #AI
[[ -n "$TARGET_ESCAPED" ]] || exit 99
sed -Ei "s|$TARGET_ESCAPED/?|/|" '/etc/zfs/zfs-list.cache/'*
unset TARGET_ESCAPED
systemctl enable zfs.target
systemctl enable zfs-import-cache
systemctl enable zfs-mount
systemctl enable zfs-import.target
systemctl enable zfs-zed
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE zfs_force=0" ## Apparently, some implementations default this to `1`, which has been known to cause corruption. (https://github.com/openzfs/zfs/issues/12842#issuecomment-1328943097)

## Prettify zpool display
echo ':: Prettifying zpool display...'
cat > /etc/zfs/vdev_id.conf <<'EOF'
## ATA HDDs
alias hdd ata-H*
alias hdd ata-IC*
alias hdd ata-M*
alias hdd ata-MX*
alias hdd ata-ST*
alias hdd ata-WD*

## ATA SSDs
alias ssd ata-CSSD*
alias ssd ata-CT*
alias ssd ata-MT*
alias ssd ata-OCZSSD*
alias ssd ata-SSD*

## Other
alias mdm md-*
alias nvm nvme-*
alias usb usb-*
alias dev wwn-*
EOF
echo 'Make sure to import your pools with `import -d /dev/disk/by-id`! Else, you will fail to import when `/dev/sdX` changes. '

## Configure ZFS
echo ':: Configuring ZFS...'
eval "$ENV_TUNE_ZFS_SCRIPT"
## I'm creating a service so that I have the option of re-running the script on each boot, but it should be enough to run it just the once, so I will leave the service disabled by default.
TUNE_ZFS_SERVICE='tune-zfs.service'
cat > "/etc/systemd/system/$TUNE_ZFS_SERVICE" <<EOF
[Unit]
Description=Configure system-wide ZFS settings
DefaultDependencies=no
Requires=zfs.target
After=zfs-import.target zfs.target
Before=multi-user.target
ConditionPathExists=$ENV_TUNE_ZFS_SCRIPT
[Service]
ExecStart=$ENV_TUNE_ZFS_SCRIPT
Type=oneshot
TimeoutSec=30
[Install]
WantedBy=multi-user.target
EOF
# systemctl daemon-reload ## Shouldn't run from chroot.
# systemctl enable "$TUNE_ZFS_SERVICE" #NOTE: No `--now` because we're in a chroot.
unset TUNE_ZFS_SERVICE

## Tune I/O
echo ':: Tuning I/O...'
TUNE_IO_SERVICE='tune-io.service'
cat > "/etc/systemd/system/$TUNE_IO_SERVICE" <<EOF
[Unit]
Description=Configure system-wide block-device settings
RefuseManualStop=yes
ConditionPathExists=$ENV_TUNE_IO_SCRIPT
[Service]
ExecStart=$ENV_TUNE_IO_SCRIPT
# ExecStopPost=/bin/rm -f /run/tune-io.env
Type=oneshot
TimeoutSec=10
[Install]
WantedBy=multi-user.target
EOF
systemctl enable "$TUNE_IO_SERVICE" #NOTE: No `--now` because we're in a chroot.
cat > /etc/udev/rules.d/90-tune-io.rules <<EOF
ACTION=="add|change", SUBSYSTEM=="block", DEVTYPE=="disk", ENV{DEVNAME}!="", RUN+="/bin/systemctl start --no-block $TUNE_IO_SERVICE"
EOF
udevadm control --reload-rules
unset TUNE_IO_SERVICE
