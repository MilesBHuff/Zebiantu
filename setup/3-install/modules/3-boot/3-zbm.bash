#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

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
