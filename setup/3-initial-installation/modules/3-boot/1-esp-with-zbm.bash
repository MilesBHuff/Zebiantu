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

## Create EFI bootloader
echo ':: Creating EFI bootloader...'
apt install -y git
cd /usr/local/src
REPO='zfsbootmenu'
[[ ! -d "$REPO" ]] && git clone "https://github.com/zbm-dev/$REPO.git"
cd "$REPO"
unset REPO
cp -r ./etc/zfsbootmenu /etc/
mkdir -p /etc/zfsbootmenu/generate-zbm.pre.d /etc/zfsbootmenu/generate-zbm.post.d /etc/zfsbootmenu/mkinitcpio.hooks.d
ZBM_EFI_DIR="$ESP_DIR/EFI/ZBM"
cat > /etc/zfsbootmenu/config.yaml <<EOF
## man 5 generate-zbm
Global:
  ManageImages: true
  InitCPIO: false
  DracutConfDir: /etc/zfsbootmenu/dracut.conf.d
  InitCPIOConfig: /etc/zfsbootmenu/mkinitcpio.conf
  InitCPIOHookDirs: [/etc/zfsbootmenu/mkinitcpio.hooks.d]
  BootMountPoint: $ESP_DIR
# Version: %current
# DracutFlags: []
# InitCPIOFlags: []
  PreHooksDir: /etc/zfsbootmenu/generate-zbm.pre.d
  PostHooksDir: /etc/zfsbootmenu/generate-zbm.post.d
Kernel:
  CommandLine: ro quiet loglevel=5 init_on_alloc=0
# Path: ''
# Version: ''
# Prefix: ''
Components:
  Enabled: false
  ImageDir: $ZBM_EFI_DIR
  Versions: 3
EFI:
  Enabled: true
  ImageDir: $ZBM_EFI_DIR
  Versions: 3
# Stub: /usr/lib/systemd/boot/efi/linuxx64.efi.stub
# SplashImage: /etc/zfsbootmenu/splash.bmp
# DeviceTree: ''
EOF
cat > /etc/zfsbootmenu/generate-zbm.post.d/99-portablize.sh <<EOF ; chmod +x '/etc/zfsbootmenu/generate-zbm.post.d/99-portablize.sh'
#!/bin/sh
cd "$ESP_DIR/EFI"
mkdir -p BOOT ZBM
SRC=\$(ls -t1 ./ZBM | grep -i '.EFI$' | head -n 1)
[ -z "\$SRC" ] && exit 1
SRC="ZBM/\$SRC"
DEST='BOOT/BOOTX64.EFI'
cp -fa "\$SRC" "\$DEST.new"
mv -f "\$DEST.new" "\$DEST"
EOF
read -rp "Don't let kexec-tools handle reboots by default; it is an unsupported scenario and results in a series of bugs. If you ever want to kexec into a small point-release kernel, explicitly request it. " _; unset _
apt install -y bsdextrautils curl dracut-core efibootmgr fzf kexec-tools libsort-versions-perl libboolean-perl libyaml-pp-perl mbuffer systemd-boot-efi
# apt-mark auto bsdextrautils dracut-core fzf libboolean-perl libsort-versions-perl libyaml-pp-perl mbuffer
make core dracut
cd "$CWD"
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE quiet loglevel=5"

## Set up ZFS in the initramfs
echo ':: Configuring the initramfs to support ZFS...'
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE init_on_alloc=0" ## `=1` causes major performance issues for ZFS. `=0` used to be the default. The minor and theoretical security improvements are not worth this much of a performance hit, and they only set it to `=1` in the first place because on non-ZFS systems it does not substantially impact performance.
case $DISTRO in
    1) apt install -y -t "$DEBIAN_VERSION-backports" zfs-initramfs ;;
    2) apt install -y -t "$UBUNTU_VERSION-backports" zfs-initramfs ;;
esac
KEYDIR=/etc/zfs/keys
install -m 700 -d "$KEYDIR"
KEYFILE="$KEYDIR/$ENV_POOL_NAME_OS.key"
if [[ ! -f "$KEYFILE" ]]; then
    install -m 600 '/dev/null' "$KEYFILE"
    read -rp "A file is about to open; enter your ZFS encryption password into it. This is necessary to prevent double-prompting during boot. Press 'Enter' to continue. " _; unset _
    nano "$KEYFILE"
fi
zfs set keylocation=file://"$KEYFILE" "$ENV_POOL_NAME_OS"
echo 'UMASK=0077' > /etc/initramfs-tools/conf.d/umask.conf
echo "FILES=\"$KEYDIR/*\"" > /etc/initramfs-tools/conf.d/99-zfs-keys.conf
unset KEYDIR KEYFILE

#TODO: Make ZBM host a dropbear ssh service, to enable manual remote unlocks. Ideally, this only starts when unlocking fails.
