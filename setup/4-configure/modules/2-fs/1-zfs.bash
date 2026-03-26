#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script.
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE init_on_alloc=0" ## `=1` causes major performance issues for ZFS. `=0` used to be the default. The minor and theoretical security improvements are not worth this much of a performance hit, and they only set it to `=1` in the first place because on non-ZFS systems it does not substantially impact performance.

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
systemctl daemon-reload
systemctl enable --now "$TUNE_ZFS_SERVICE"
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
systemctl enable --now "$TUNE_IO_SERVICE"
cat > /etc/udev/rules.d/90-tune-io.rules <<EOF
ACTION=="add|change", SUBSYSTEM=="block", DEVTYPE=="disk", ENV{DEVNAME}!="", RUN+="/bin/systemctl start --no-block $TUNE_IO_SERVICE"
EOF
udevadm control --reload-rules
unset TUNE_IO_SERVICE

## Get zvol necessities
echo ':: Installing zvol filesystems...'
apt install -y xfsprogs
