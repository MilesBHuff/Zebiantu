#!/usr/bin/env bash
## Special thanks to https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Bookworm%20Root%20on%20ZFS.html
## Also thanks to ChatGPT (not for code, but for helping with some installataion steps)

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
set -e

## Configure hostname
echo ':: Configuring hostname...'
HOSTNAME='artemis'
hostname "$HOSTNAME"
hostname > '/etc/hostname'
echo "127.0.1.1 $HOSTNAME" >> '/etc/hosts'

## Configure network
echo ':: Configuring network...'
ip addr show
read -p "Copy the interface name you want to use, and paste it here; then press 'Enter': " INTERFACE_NAME
cat > "/etc/network/interfaces.d/$INTERFACE_NAME" <<EOF
auto $INTERFACE_NAME
iface $INTERFACE_NAME inet dhcp
EOF

## Configure apt
echo ':: Configuring apt...'
cat > /etc/apt/sources.list <<EOF
deb      http://deb.debian.org/debian/                bookworm                   main contrib non-free-firmware non-free
deb-src  http://deb.debian.org/debian/                bookworm                   main contrib non-free-firmware non-free

deb      http://deb.debian.org/debian/                bookworm-backports         main contrib non-free-firmware non-free
deb-src  http://deb.debian.org/debian/                bookworm-backports         main contrib non-free-firmware non-free

deb      http://deb.debian.org/debian/                bookworm-backports-sloppy  main contrib non-free-firmware non-free
deb-src  http://deb.debian.org/debian/                bookworm-backports-sloppy  main contrib non-free-firmware non-free

deb      http://security.debian.org/debian-security/  bookworm-security          main contrib non-free-firmware non-free
deb-src  http://security.debian.org/debian-security/  bookworm-security          main contrib non-free-firmware non-free

deb      http://deb.debian.org/debian/                bookworm-updates           main contrib non-free-firmware non-free
deb-src  http://deb.debian.org/debian/                bookworm-updates           main contrib non-free-firmware non-free
EOF

## Configure the system
echo ':: Configuring system...'
apt install -y locales
dpkg-reconfigure locales
apt install -y console-setup
read -p "Note: 8x16 is considered kinda the standard size. Bold is easiest to read. VGA is probably your best bet. Press 'Enter' to continue. " FOO
dpkg-reconfigure console-setup
dpkg-reconfigure keyboard-configuration
dpkg-reconfigure tzdata

## Set up /etc/skel
echo ':: Creating user configs...'
apt install -y tmux
echo 'set -g status-position top' > /etc/skel/.tmux.conf
echo >> /etc/.bashrc
echo 'shopt -q login_shell && [[ -x $(which tmux) ]] && [[ ! -n "$TMUX" ]] && exec tmux' >> /etc/.bashrc

## Configure users
echo ':: Configuring users...'
echo 'Please enter a complex password for the root user: '
passwd
for FILE in $(ls -A /etc/skel); do cp "$FILE" /root/; done
read -p "Please enter a username for your personal user: " USERNAME
adduser "$USERNAME"

## Get our packages up-to-date
echo ':: Updating...'
apt update
apt full-upgrade -y
apt install -y unattended-upgrades

## Install Linux
echo ':: Installing Linux...'
apt install -y -t bookworm-backports linux-image-amd64 linux-headers-amd64 dkms

## Install important but missing compression algorithm
echo ':: Installing LZ4...'
apt install -y lz4
echo lz4 >> /etc/initramfs-tools/modules

## Install and configure ZFS
echo ':: Installing ZFS...'
apt install -y -t bookworm-backports zfsutils-linux zfs-dkms
# echo 'REMAKE_INITRD=yes' >> '/etc/dkms/zfs.conf' #NOTE: Needed on ZFS < 2.2, deprecated on ZFS >= 2.2
mkdir -p '/etc/zfs/zfs-list.cache'
touch '/etc/zfs/zfs-list.cache/os-pool'
# zed -F
sed -Ei "s|$TARGET/?|/|" '/etc/zfs/zfs-list.cache/'*
systemctl enable zfs.target
systemctl enable zfs-import-cache
systemctl enable zfs-mount
systemctl enable zfs-import.target

## Install and configure EFI bootloader
echo ':: Installing EFI bootloader...'
mkdir -p /boot/esp
apt install -y dosfstools mdadm
# systemctl enable mdadm-raid
read -p 'Run this command outside of chroot and paste the result: `$(lsblk -o uuid "/dev/md/$ENV_NAME_ESP" | tail -n 1)` ' ESP_UUID
echo "UUID=$ESP_UUID /boot/esp vfat noatime,lazytime,nofail,x-systemd.device-timeout=5s,iocharset=utf8,umask=0022,fmask=0133,dmask=0022 0 0" > '/etc/fstab' #FIXME: `sync` causes writes to never finish?
mount /boot/esp
apt install -y git
CWD=$(pwd)
cd /usr/local/src
git clone 'https://github.com/zbm-dev/zfsbootmenu'
cd zfsbootmenu
cp -r ./etc/zfsbootmenu /etc/
mkdir -p /etc/zfsbootmenu/generate-zbm.pre.d /etc/zfsbootmenu/generate-zbm.post.d /etc/zfsbootmenu/mkinitcpio.hooks.d
cat > /etc/zfsbootmenu/config.yaml <<EOF
## man 5 generate-zbm
Global:
  ManageImages: true
  InitCPIO: false
  DracutConfDir: /etc/zfsbootmenu/dracut.conf.d
  InitCPIOConfig: /etc/zfsbootmenu/mkinitcpio.conf
  InitCPIOHookDirs: [/etc/zfsbootmenu/mkinitcpio.hooks.d]
  BootMountPoint: /boot/esp
# Version: %current
# DracutFlags: []
# InitCPIOFlags: []
  PreHooksDir: /etc/zfsbootmenu/generate-zbm.pre.d
  PostHooksDir: /etc/zfsbootmenu/generate-zbm.post.d
#Kernel:
# CommandLine: ''
# Path: ''
# Version: ''
# Prefix: ''
Components:
  Enabled: false
  ImageDir: /boot/esp/EFI/ZBM
  Versions: 3
EFI:
  Enabled: true
  ImageDir: /boot/esp/EFI/ZBM
  Versions: 3
# Stub: /usr/lib/systemd/boot/efi/linuxx64.efi.stub
# SplashImage: /etc/zfsbootmenu/splash.bmp
# DeviceTree: ''
Kernel:
  CommandLine: ro quiet loglevel=5
EOF
cat > /etc/zfsbootmenu/generate-zbm.post.d/99-portablize.sh <<'EOF'
#!/bin/sh
cd /boot/esp/EFI
mkdir -p BOOT ZBM
SRC=$(ls -t1 ./ZBM | grep -i '.EFI$' | head -n 1)
[ -z "$SRC" ] && exit 1
SRC="ZBM/$SRC"
DEST='BOOT/BOOTX64.EFI'
cp -fa "$SRC" "$DEST.new"
mv -f "$DEST.new" "$DEST"
EOF
chmod +x /etc/zfsbootmenu/generate-zbm.post.d/99-portablize.sh
read -p "Don't let kexec-tools handle reboots by default; it is an unsupported scenario and results in a series of bugs. If you ever want to kexec into a small point-release kernel, explicitly request it. " FOO
apt install -y bsdextrautils curl dracut-core efibootmgr fzf kexec-tools libsort-versions-perl libboolean-perl libyaml-pp-perl mbuffer systemd-boot-efi
apt-mark auto bsdextrautils dracut-core fzf libboolean-perl libsort-versions-perl libyaml-pp-perl mbuffer
make core dracut
generate-zbm
cd "$CWD"
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE quiet loglevel=5"
echo 'WARN: To use SecureBoot, you need to generate a private key, enroll it in your NVRAM, and sign your ZBM image with it.' >&2

## Set up ZFS in the initramfs
echo ':: Configuring the initramfs to support ZFS...'
apt install -y zfs-initramfs
KEYDIR=/etc/zfs/keys
chmod 700 "$KEYDIR"
KEYFILE="$KEYDIR/$ENV_POOL_NAME_OS.key"
touch "$KEYFILE"
read -p "A file is about to open; enter your ZFS encryption password into it. This is necessary to prevent double-prompting during boot. Press 'Enter' to continue. " FOO
nano "$KEYFILE"
zfs set keylocation=file://"$KEYFILE" "$ENV_POOL_NAME_OS"
echo 'UMASK=0077' > /etc/initramfs-tools/conf.d/umask.conf
echo "FILES=\"$KEYDIR/*\"" > /etc/initramfs-tools/conf.d/99-zfs-keys.conf

## Prettify zpool display
cat > /etc/zfs/vdev_id.conf <<EOF
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
alias mdm ata-md*
alias nvm ata-nvme*
alias usb ata-usb*
alias dev ata-wwn*
EOF
echo 'Make sure to import your pools with `import -d /dev/disk/by-id`! Else, you will fail to import when `/dev/sdX` changes. '

## Enable swap
echo ':: Configuring swap...'
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE zswap.enabled=1 zswap.max_pool_percent=12 zswap.compressor=lzo" #NOTE: Fractional percents (eg, `12.5`) are not possible.
apt install -y systemd-zram-generator
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = "ram * 0.375"
compression-algorithm = "zstd"
swap-priority = 32767
#TODO: Specify zstd level.

#WARN: Not worth it: compression DRAMATICALLY slows RAM; more, tmpfs without a limit swaps, meaning zswap + zram swap will catch and compress unused tmpfs data. That means dynamic compression instead of universal compression, and that’s a clearly superior scenario.
# [zram1]
# zram-size = "1G"
# compression-algorithm = "lz4"
# fs-type = "ext4"
# fs-create-options = "-E lazy_itable_init=0,lazy_journal_init=0 -m0 -O none,extent,dir_index,extra_isize=256 -T small" #NOTE: Enable `metadata_csum` if you don’t trust your RAM.
## No point in `lazytime` when the filesystem is in RAM.
# options = "X-mount.mode=1777,noatime,discard"
## Yes, this should generate and mount before anything needs it.
# mount-point = "/tmp"

#NOTE: /run is mounted as tmpfs extremely early, before generators run; consequently, it is not possible to use zram for it (at least not in *this* way).
EOF
systemctl daemon-reload
systemctl start systemd-zram-setup@zram0

## Configure `/tmp` as tmpfs
echo ':: Configuring `/tmp`...'
cp /usr/share/systemd/tmp.mount /etc/systemd/system/
systemctl enable tmp.mount
mkdir -p /etc/systemd/system/tmp.mount.d
cat > /etc/systemd/system/tmp.mount.d/override.conf <<EOF
[Mount]
Options=mode=1777,nosuid,nodev,size=5G,noatime
## 5G is enough space to have 1G free while extracting a 4G archive. 1G is plenty for normal operation. ## No point in `lazytime` when the filesystem is in RAM.
EOF
cat > /etc/systemd/system/console-setup.service.d/override.conf <<EOF
[Unit]
Requires=tmp.mount
After=tmp.mount
EOF #BUG: Resolves an issue where console-setup can happen shortly before tmpfs mounts and accordingly fail when tmpfs effectively deletes /tmp while console-setup is happening.
systemctl daemon-reload

## Install MAC
echo ':: Enabling Mandatory Access Control...'
apt install -y apparmor apparmor-utils apparmor-notify apparmor-profiles apparmor-profiles-extra
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE apparmor=1 security=apparmor"

## Install daemons
echo ':: Installing daemons...'
## Generally useful
apt install -y chrony clamav clamav-daemon systemd-oomd
systemctl enable clamav-daemon
systemctl enable clamav-freshclam
## Niche
apt install -y rasdaemon fail2ban nut-server
systemctl enable fail2ban
systemctl enable rasdaemon
systemctl enable nut-server
systemctl enable nut-monitor
## Follow-up
systemctl mask systemd-coredump.socket systemd-coredump@.service

## Install firmware
echo ':: Installing firmware, drivers, and tools...'
## General firmware
apt install -y firmware-linux-free firmware-linux-nonfree firmware-misc-nonfree
## General firmware tools
apt install -y fwupd iasl
## General hardware tools
apt install -y cpufrequtils i2c-tools ethtool fancontrol lm-sensors lshw net-tools pciutils read-edid rng-tools-debian smartmontools tpm2-tools usbutils sysstat dmsetup
# sensors detect
systemctl enable rng-tools-debian
## Specific firmware
apt install -y amd64-microcode firmware-amd-graphics firmware-mellanox firmware-realtek
## Specific tools
apt install -y ipmitool mstflint openseachest
## Proprietary tools
# install STORCLI MFT
# systemctl enable mst

## Install applications
echo ':: Installing applications...'
## Applications that need configuration
tasksel --new-install
apt install -y popularity-contest
## Common applications
apt install -y cups rsync unzip
## Niche applications
apt install -y sanoid

## More configuration
echo ':: Additional configurations...'
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE page_alloc.shuffle=1"
read -p 'Please enter your wireless regulatory domain: ('US' for the USA) ' REGDOM
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE cfg80211.ieee80211_regdom=$REGDOM"

## Disable various compressions (ZFS does compression for us.)
echo ':: Avoiding double-compression...'
FILE='/etc/initramfs-tools/initramfs.conf'
cat "$FILE" | sed -r 's/^(COMPRESS)=.*/\1=lz4/' | sed -ir 's/^# (COMPRESS_LEVEL)=.*/\1=0/' '/etc/initramfs-tools/initramfs.conf' > "$FILE.new"
mv -f "$FILE.new" "$FILE"
for FILE in /etc/logrotate.conf /etc/logrotate.d/*; do
    if grep -Eq '(^|[^#y])compress' "$FILE"; then
        cat "$FILE" | sed -r 's/(^|[^#y])(compress)/\1#\2/' > "$FILE.new"
        mv "$FILE.new" "$FILE"
    fi
done

## Reconfigure FSH
echo ':: Modifying filesystem hierarchy...'
bash ../configure-filesystem-hierarchy.bash

# ## Better bitmap font
# echo ':: Installing better bitmap font...'
# FILE='/etc/default/console-setup'
# cd /tmp
# git clone https://github.com/sunaku/tamzen-font.git
# cd tamzen-font/bdf
# apt install -y bdf2psf
# mkdir psf
# B2P='/usr/share/bdf2psf'
# bdf2psf --fb Tamzen8x16b.bdf "$B2P/standard.equivalents" "$B2P/ascii.set+$B2P/linux.set+$B2P/useful.set" 512 psf/TamzenBold8x16.psf
# cd psf
# gzip --best *
# cp * /usr/local/share/consolefonts/
# cd /usr/local/share/consolefonts
# rm -rf /tmp/tamzen-font
# ln -s * /usr/share/kbd/consolefonts/
# cat "$FILE" | sed -r 's/^(FONTFACE)=".*/\1="TamzenBold"/' | sed -ir 's/^# (FONTSIZE)=.*/\1="8x16/' '/etc/initramfs-tools/initramfs.conf' > "$FILE.new"
# cd "$CWD"

## Wrap up
echo ':: Wrapping up...'
zfs set org.zfsbootmenu:commandline="$KERNEL_COMMANDLINE" "$ENV_POOL_NAME_OS/OS/debian"
update-initramfs -u
zfs snapshot -r os-pool@install-debian

## Done
exit 0
