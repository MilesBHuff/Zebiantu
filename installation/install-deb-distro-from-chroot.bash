#!/usr/bin/env bash
function helptext {
    echo "Usage: install-deb-distro-from-chroot.bash"
    echo
    echo 'This is a one-shot script that finishes setting up Debian or Ubuntu in a chroot.'
    echo 'WARN: Although this is intended as a one-shot script, it *should* be more-or-less idempotent; just try to maintain consistent user responses between runs.'
}
## Special thanks to https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Bookworm%20Root%20on%20ZFS.html
## My thanks to ChatGPT (not as the author of this code (that's me), but for helping with my endless questions and providing advice)
set -euo pipefail

function idempotent_append {
    ## $1: What to append
    ## $2: Where to append it
    [[ ! -f "$2" ]] && touch "$2"
    grep -Fqx -- "$1" "$2" || printf '%s\n' "$1" >> "$2"
}

## Get environment
CWD=$(pwd)
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
if [[
    -z "$DEBIAN_VERSION" ||\
    -z "$DISTRO" ||\
    -z "$TARGET" ||\
    -z "$UBUNTU_VERSION"
]]; then
    echo "ERROR: This script is designed to be run from a \`chroot\` spawned by \`install-deb-distro.bash\`." >&2
    exit 4
fi

## Configure hostname
echo ':: Configuring hostname...'
read -p "What unqualified hostname would you like?: " HOSTNAME
hostname "$HOSTNAME"
hostname > '/etc/hostname'
sed -i '/^127\.0\.1\.1 /d' '/etc/hosts'
idempotent_append "127.0.1.1 $HOSTNAME" '/etc/hosts'

echo ':: Configuring Wi-Fi...'
read -p 'Please enter your wireless regulatory domain: ("US" for the USA) ' REGDOM
KERNEL_COMMANDLINE="cfg80211.ieee80211_regdom=$REGDOM"
unset REGDOM
apt install -y rfkill
cat > /etc/udev/rules.d/80-rfkill-wifi.rules <<EOF
SUBSYSTEM=="rfkill", ATTR{type}=="wlan", ACTION=="add|change", RUN+="/usr/sbin/rfkill block wifi"
EOF

echo ':: Configuring Wake-On-LAN...'
cat > /etc/udev/rules.d/99-wol.rules <<EOF
ACTION=="add", SUBSYSTEM=="net", KERNEL=="en*", RUN+="/usr/sbin/ethtool -s %k wol g"
ACTION=="add", SUBSYSTEM=="net", KERNEL=="eth*", RUN+="/usr/sbin/ethtool -s %k wol g"
EOF

## Configure apt
echo ':: Configuring apt...'
case $DISTRO in
    1) cat > /etc/apt/sources.list <<EOF
deb      http://deb.debian.org/debian/                $DEBIAN_VERSION                   main contrib non-free-firmware non-free
deb-src  http://deb.debian.org/debian/                $DEBIAN_VERSION                   main contrib non-free-firmware non-free

deb      http://deb.debian.org/debian/                $DEBIAN_VERSION-backports         main contrib non-free-firmware non-free
deb-src  http://deb.debian.org/debian/                $DEBIAN_VERSION-backports         main contrib non-free-firmware non-free

deb      http://deb.debian.org/debian/                $DEBIAN_VERSION-backports-sloppy  main contrib non-free-firmware non-free
deb-src  http://deb.debian.org/debian/                $DEBIAN_VERSION-backports-sloppy  main contrib non-free-firmware non-free

deb      http://security.debian.org/debian-security/  $DEBIAN_VERSION-security          main contrib non-free-firmware non-free
deb-src  http://security.debian.org/debian-security/  $DEBIAN_VERSION-security          main contrib non-free-firmware non-free

deb      http://deb.debian.org/debian/                $DEBIAN_VERSION-updates           main contrib non-free-firmware non-free
deb-src  http://deb.debian.org/debian/                $DEBIAN_VERSION-updates           main contrib non-free-firmware non-free
EOF ;;
    2) cat > /etc/apt/sources.list.d/official-package-repositories.list <<EOF
deb http://mirror.brightridge.com/ubuntuarchive/  $UBUNTU_VERSION            main restricted universe multiverse
deb http://archive.canonical.com/ubuntu/          $UBUNTU_VERSION            partner
deb http://mirror.brightridge.com/ubuntuarchive/  $UBUNTU_VERSION-updates    main restricted universe multiverse
deb http://mirror.brightridge.com/ubuntuarchive/  $UBUNTU_VERSION-backports  main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/            $UBUNTU_VERSION-security   main restricted universe multiverse
EOF ;;
esac
set +e
shopt -s nullglob
${EDITOR:-nano} /etc/apt/sources.list.d/*
shopt -u nullglob
set -e

## Configure the system
echo ':: Configuring system...'
apt install -y locales
dpkg-reconfigure locales
apt install -y console-setup
read -p "Note: 8x16 is considered kinda the standard size. Bold is easiest to read. VGA is probably your best bet. Press 'Enter' to continue. " FOO; unset FOO
dpkg-reconfigure console-setup
dpkg-reconfigure keyboard-configuration
dpkg-reconfigure tzdata

## Set up /etc/skel
echo ':: Creating user configs...'
apt install -y tmux
echo 'set -g status-position top' > /etc/skel/.tmux.conf
idempotent_append 'shopt -q login_shell && command -v tmux && [[ ! -n "$TMUX" ]] && exec tmux' '/etc/skel/.bashrc'

## Configure users
echo ':: Configuring users...'
if ! passwd -S root 2>/dev/null | grep -q ' P '; then
    echo 'Please enter a complex password for the root user: '
    passwd
fi
cp -a /etc/skel/. /root/
read -p "Please enter a username for your personal user: " USERNAME
id "$USERNAME" >/dev/null 2>&1 || adduser "$USERNAME"
export USERNAME

## Get our packages up-to-date
echo ':: Upgrading packages...'
apt update
apt full-upgrade -y
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

## Install build tools
apt install -y build-essential pkg-config

## Install Linux
echo ':: Installing Linux...'
case $DISTRO in
    1) apt install -y -t "$DEBIAN_VERSION-backports" linux-image-amd64 linux-headers-amd64 dkms ;;
    2) apt install -y -t "$UBUNTU_VERSION-backports" linux-image-generic linux-headers-generic dkms ;;
esac

## Install systemd
echo ':: Installing systemd...'
apt install -y systemd
hostnamectl set-hostname $(hostname) ## Just in case systemd knows of additional places it needs setting.

## Install and configure ZFS
echo ':: Installing ZFS...'
case $DISTRO in
    1) apt install -y -t "$DEBIAN_VERSION-backports" zfsutils-linux zfs-dkms ;;
    2) apt install -y -t "$UBUNTU_VERSION-backports" zfsutils-linux ;;
esac
ZFS_VERSION="$(zfs --version | head -n1 | cut -c5-)"
dpkg --compare-versions "$ZFS_VERSION" lt 2.2 && idempotent_append 'REMAKE_INITRD=yes' '/etc/dkms/zfs.conf' ## Needed on ZFS < 2.2, deprecated on ZFS >= 2.2
mkdir -p '/etc/zfs/zfs-list.cache'
touch "/etc/zfs/zfs-list.cache/$ENV_POOL_NAME_OS"
# zed -F
TARGET_ESCAPED=$(printf '%s\n' "$TARGET" | sed 's/[\/&]/\\&/g') #AI
sed -Ei "s|$TARGET_ESCAPED/?|/|" '/etc/zfs/zfs-list.cache/'*
systemctl enable zfs.target
systemctl enable zfs-import-cache
systemctl enable zfs-mount
systemctl enable zfs-import.target

## Install and configure EFI bootloader
echo ':: Installing EFI bootloader...'
mkdir -p /boot/esp
apt install -y dosfstools mdadm
read -p 'Run this command outside of chroot and paste the result: `$(lsblk -o uuid "/dev/md/$ENV_NAME_ESP" | tail -n 1)` ' ESP_UUID
echo "UUID=$ESP_UUID /boot/esp vfat noatime,lazytime,nofail,x-systemd.device-timeout=5s,iocharset=utf8,umask=0022,fmask=0133,dmask=0022 0 0" > '/etc/fstab' #FIXME: `sync` causes writes to never finish?
unset ESP_UUID
mount /boot/esp
apt install -y git
cd /usr/local/src
REPO='zfsbootmenu'
[[ ! -d "$REPO" ]] && git clone "https://github.com/zbm-dev/$REPO.git"
cd "$REPO"
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
Kernel:
  CommandLine: ro quiet loglevel=5 init_on_alloc=0
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
EOF
cat > /etc/zfsbootmenu/generate-zbm.post.d/99-portablize.sh <<EOF
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
read -p "Don't let kexec-tools handle reboots by default; it is an unsupported scenario and results in a series of bugs. If you ever want to kexec into a small point-release kernel, explicitly request it. " FOO; unset FOO
apt install -y bsdextrautils curl dracut-core efibootmgr fzf kexec-tools libsort-versions-perl libboolean-perl libyaml-pp-perl mbuffer systemd-boot-efi
# apt-mark auto bsdextrautils dracut-core fzf libboolean-perl libsort-versions-perl libyaml-pp-perl mbuffer
make core dracut
generate-zbm
cd "$CWD"
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE quiet loglevel=5"
echo 'WARN: To use SecureBoot, you need to generate a private key, enroll it in your NVRAM, and sign your ZBM image with it.' >&2 #TODO

## Set up ZFS in the initramfs
echo ':: Configuring the initramfs to support ZFS...'
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE init_on_alloc=0" ## `=1` causes major performance issues for ZFS. `=0` used to be the default. The minor and theoretical security improvements are not worth this much of a performance hit, and they only set it to `=1` in the first place because on non-ZFS systems it does not substantially impact performance.
case $DISTRO in
    1) apt install -y -t "$DEBIAN_VERSION-backports" zfs-initramfs ;;
    2) apt install -y -t "$UBUNTU_VERSION-backports" zfs-initramfs ;;
esac
KEYDIR=/etc/zfs/keys
chmod 700 "$KEYDIR"
KEYFILE="$KEYDIR/$ENV_POOL_NAME_OS.key"
if [[ ! -f "$KEYFILE" ]]; then
    touch "$KEYFILE"
    chmod 600 "$KEYFILE"
    read -p "A file is about to open; enter your ZFS encryption password into it. This is necessary to prevent double-prompting during boot. Press 'Enter' to continue. " FOO; unset FOO
    nano "$KEYFILE"
fi
zfs set keylocation=file://"$KEYFILE" "$ENV_POOL_NAME_OS"
echo 'UMASK=0077' > /etc/initramfs-tools/conf.d/umask.conf
echo "FILES=\"$KEYDIR/*\"" > /etc/initramfs-tools/conf.d/99-zfs-keys.conf
unset KEYDIR KEYFILE

## Install important but potentially missing compression algorithms and tooling
echo ':: Installing compressiony things...'
apt install -y gzip lz4 lzop unrar unzip zip zstd
idempotent_append 'lz4' '/etc/initramfs-tools/modules'

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
alias mdm md-*
alias nvm nvme-*
alias usb usb-*
alias dev wwn-*
EOF
echo 'Make sure to import your pools with `import -d /dev/disk/by-id`! Else, you will fail to import when `/dev/sdX` changes. '

## Enforce mount options
## ZFS does not provide properties for all of the mount options it supports (like `lazytime`), so we have to specify it manually when mounting datasets or monkeypatch `zfs` to do it by default.
## Linux's default mount options include `relatime` and lack `lazytime`, which is suboptimal for performance and longevity. The only way to change the defaults is to monkeypatch `mount`.
## A lot of system mounts explicitly declare `relatime` when nothing in them actually uses atimes. These need manual correction.
BASENAME=remount-options
SCRIPT="/usr/local/sbin/.$BASENAME"

SERVICE="/etc/systemd/system/$BASENAME-normal.service"
cat > "$SERVICE" <<EOF
[Unit]
Description=Retroactively apply mount options to all non-zfs mounts.
After=local-fs.target
# Requires=local-fs.target
[Service]
Type=oneshot
ExecStart=$SCRIPT mount
[Install]
WantedBy=multi-user.target
EOF
systemctl enable "$SERVICE"

SERVICE="/etc/systemd/system/$BASENAME-zfs.service"
cat > "$SERVICE" <<EOF
[Unit]
Description=Retroactively apply mount options to all zfs mounts.
After=zfs-mount.service
Requires=zfs-mount.service
[Service]
Type=oneshot
ExecStart=$SCRIPT zfs
[Install]
WantedBy=multi-user.target
EOF
systemctl enable "$SERVICE"

cat > "$SCRIPT" <<EOF
#!/bin/sh
AWK_SCRIPT='{ print $2, $4 }'
[ "$1" = 'mount' ] && AWK_SCRIPT='$3!="zfs" '"$AWK_SCRIPT" ||\
[ "$1" = 'zfs'   ] && AWK_SCRIPT='$3=="zfs" '"$AWK_SCRIPT"
awk "$AWK_SCRIPT" /proc/self/mounts | while read -r MOUNT_PATH MOUNT_OPTS; do
    REMOUNT_OPTS=''
    case ",$MOUNT_OPTS," in
        *,lazytime,*|*,sync,*|*,ro,*) ;; #FIXME: There is probably no point in enabling `lazytime` on RAM-based filesystems.
        *) REMOUNT_OPTS="$REMOUNT_OPTS,lazytime" ;;
    esac
    case ",$MOUNT_OPTS," in
        # *,noatime,*|*,relatime,*|*,atime,*) ;;
        *,noatime,*|*,atime,*) ;; ## A lot of filesystems are explicitly mounted with relatime for no reason, and accordingly need to be overridden -- This means that filesystems that *do* need atimes have to set `atime`, not `relatime`...
        *) REMOUNT_OPTS="$REMOUNT_OPTS,noatime" ;;
    esac
    if [ -n "$REMOUNT_OPTS" ]; then
        mount -o "remount$REMOUNT_OPTS" "$MOUNT_PATH"
    fi
done
exit 0
EOF
chmod 0755 "$SCRIPT"

SCRIPT=/usr/local/sbin/mount
cat > "$SCRIPT" <<EOF
#!/bin/sh
exec /usr/bin/mount -o noatime,lazytime "$@"
EOF
chmod 0755 "$SCRIPT"

SCRIPT=/usr/local/sbin/zfs
cat > "$SCRIPT" <<EOF
#!/bin/sh
[ "$1" != mount ] && exec /usr/sbin/zfs "$@"
shift
exec /usr/sbin/zfs mount -o lazytime "$@"
EOF
chmod 0755 "$SCRIPT"

unset BASENAME SCRIPT SERVICE

## Enable swap
echo ':: Configuring swap...'
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE zswap.enabled=1 zswap.max_pool_percent=17 zswap.compressor=lzo" #NOTE: Fractional percents (eg, `12.5`) are not possible.
apt install -y systemd-zram-generator
cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = "ram * 0.3333333"
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
## 5G is enough space to have 1G free while extracting a 4G archive (the max supported by FAT32). 1G is plenty for normal operation. ## No point in `lazytime` when the filesystem is in RAM.
EOF
mkdir -p /etc/systemd/system/console-setup.service.d
cat > /etc/systemd/system/console-setup.service.d/override.conf <<EOF
[Unit]
Requires=tmp.mount
After=tmp.mount
EOF #BUG: Resolves an issue where console-setup can happen shortly before tmpfs mounts and accordingly fail when tmpfs effectively deletes /tmp while console-setup is happening.
systemctl daemon-reload

## Configure trim/discard
echo ':: Scheduling trim...'
systemctl enable fstrim.timer ## Auto-trims everything in /etc/fstab
#TODO: Auto-trim zpools, too.

## Install MAC
echo ':: Enabling Mandatory Access Control...'
apt install -y apparmor apparmor-utils apparmor-notify apparmor-profiles apparmor-profiles-extra
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE apparmor=1 security=apparmor"

## Install daemons
echo ':: Installing daemons...'
## Generally useful
apt install -y chrony clamav clamav-daemon systemd-oomd
systemctl enable chrony
systemctl enable clamav-daemon
systemctl enable clamav-freshclam
systemctl enable systemd-oomd
## Niche
apt install -y rasdaemon fail2ban
systemctl enable fail2ban
systemctl enable rasdaemon
## Follow-up
systemctl mask systemd-coredump.socket systemd-coredump@.service

## Install firmware
echo ':: Installing firmware, drivers, and tools...'
## General firmware
apt install -y firmware-linux-free firmware-linux-nonfree firmware-misc-nonfree
## General firmware tools
apt install -y fwupd iasl
## General hardware tools
KVER=$(ls /lib/modules | sort -V | tail -n1) #NOTE: Can't use `uname -r` since that'd be the LiveCD's kernel.
apt install -y linux-tools-common linux-tools-$KVER i2c-tools ethtool fancontrol lm-sensors lshw net-tools pciutils read-edid smartmontools hdparm tpm2-tools usbutils sysstat iotop dmsetup numactl numatop procps psmisc cgroup-tools mesa-utils clinfo
sensors-detect --auto

## Upgrade firmware
echo ':: Upgrading firmware...'
set +e
fwupdmgr refresh
fwupdmgr get-updates && fwupdmgr update
set -e

## Install applications
echo ':: Installing applications...'
## Applications that need configuration
[[ $DISTRO -eq 1 ]] && tasksel --new-install
apt install -y popularity-contest
## Common applications
apt install -y cups rsync
## Niche applications
# apt install -y # sanoid

## Disable or (if impossible to disable) adjust various compressions to save CPU (ZFS does compression for us extremely cheaply, and space is very plentiful on the OS drives.)
echo ':: Tweaking various compression settings...'
FILE='/etc/initramfs-tools/initramfs.conf'
cat "$FILE" | sed -r 's/^(COMPRESS)=.*/\1=zstd/' | sed -r 's/^# (COMPRESS_LEVEL)=.*/\1=0/' > "$FILE.new" ## I tested; `zstd-0` beats `lz4-0` at both speed and ratio here.
mv -f "$FILE.new" "$FILE"
for FILE in /etc/logrotate.conf /etc/logrotate.d/*; do
    if grep -Eq '(^|[^#y])compress' "$FILE"; then
        cat "$FILE" | sed -r 's/(^|[^#y])(compress)/\1#\2/' > "$FILE.new"
        mv "$FILE.new" "$FILE"
    fi
done
unset FILE

## Reconfigure FSH
echo ':: Modifying filesystem hierarchy...'
bash ./configure-filesystem-hierarchy.bash

# ## Better bitmap font
# #FIXME: It doesn't handle box-drawing characters, and it could be made to handle Powerline characters.
# echo ':: Installing better bitmap font...'
# FILE='/etc/default/console-setup'
# cd /tmp
# REPO='tamzen-font'
# [[ ! -d "$REPO" ]] && git clone "https://github.com/sunaku/$REPO.git"
# cd "$REPO/bdf"
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
# unset FILE

## Limit log size
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/max-size.conf <<EOF
[Journal]
Storage=persistent
SystemMaxUse=256M
RuntimeMaxUse=128M
EOF

## Set up `ssh`
apt install -y openssh-server
sed -Ei 's/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl enable ssh

## More configuration
echo ':: Additional configurations...'
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE page_alloc.shuffle=1"

## Set kernel commandline
echo ':: Setting kernel commandline...'
KERNEL_COMMANDLINE_DIR='/etc/zfsbootmenu/commandline'
mkdir -p "$KERNEL_COMMANDLINE_DIR"
echo "$KERNEL_COMMANDLINE" > "$KERNEL_COMMANDLINE_DIR/commandline.txt"
echo '#!/bin/sh' > "$KERNEL_COMMANDLINE_DIR/set-commandline"
echo 'BOOTFS=$(zpool get -Ho value bootfs '"$ENV_POOL_NAME_OS"')' > "$KERNEL_COMMANDLINE_DIR/set-commandline"
cat >> "$KERNEL_COMMANDLINE_DIR/set-commandline" <<EOF
COMMANDLINE="$(cat /etc/zfsbootmenu/commandline/commandline.txt | xargs | tr ' ' '\n' | sort -V | uniq | tr '\n' ' ' && echo)"
zfs set org.zfsbootmenu:commandline="$COMMANDLINE" "$BOOTFS"
zfs get org.zfsbootmenu:commandline "$BOOTFS"
EOF
export KERNEL_COMMANDLINE_DIR
update-initramfs -u

## Wrap up
echo ':: Creating snapshot...'
set +e
zfs snapshot -r "$ENV_POOL_NAME_OS@install-$DISTRO"
set -e

## Done
case "$HOSTNAME" in
    'artemis') exec ./configure-artemis.bash ;;
    'hephaestus') exec ./configure-hephaestus.bash ;;
    *) echo ':: Done.' && exit 0 ;;
esac
