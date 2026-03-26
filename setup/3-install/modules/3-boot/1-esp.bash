#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## Initialize ESP
echo ':: Initializing ESP...'
ESP_DIR='/boot/esp'
mkdir -p "$ESP_DIR"
apt install -y dosfstools mdadm
read -rp 'Run this command outside of chroot and paste the result: `$(lsblk -o uuid "/dev/md/$ENV_NAME_ESP" | tail -n 1)` ' ESP_UUID
echo "UUID=$ESP_UUID $ESP_DIR vfat noatime,lazytime,nofail,x-systemd.device-timeout=5s,iocharset=utf8,umask=0022,fmask=0133,dmask=0022 0 0" > '/etc/fstab' #NOTE: fstab doesn't exist before this, so overwriting is fine. #FIXME: For some reason, `sync` causes writes to never finish? I've removed it for the time-being.
unset ESP_UUID
mount "$ESP_DIR"
