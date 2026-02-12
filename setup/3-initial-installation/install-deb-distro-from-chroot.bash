#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob
function helptext {
    echo "Usage: install-deb-distro-from-chroot.bash"
    echo
    echo 'This is a one-shot script that finishes setting up Debian or Ubuntu in a chroot.'
    echo 'WARN: Although this is intended as a one-shot script, it *should* be more-or-less idempotent; just try to maintain consistent user responses between runs.'
    echo
    echo 'You must have SecureBoot enabled in Setup Mode (PK cleared, not enforcing), and the live system must be booted in UEFI mode.'
}
## Special thanks to https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Bookworm%20Root%20on%20ZFS.html
## Special thanks to ChatGPT for helping with my endless questions.
#TODO: Make it possible to specify what parts of the scipt to run.

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
load_envfile "$ENV_FILESYSTEM_ENVFILE" \
    ENV_NAME_ESP \
    ENV_POOL_NAME_OS \
    ENV_ZFS_ROOT
load_envfile "$ENV_SETUP_ENVFILE" \
    DEBIAN_VERSION \
    UBUNTU_VERSION \
    ENV_KERNEL_COMMANDLINE_DIR
## Load and validate variables passed-into the chroot
declare -a ENV_VARS=(
    DISTRO
    ENV_FILESYSTEM_ENVFILE
    ENV_SETUP_ENVFILE
    ENV_TUNE_IO_SCRIPT
    ENV_TUNE_ZFS_SCRIPT
    TARGET
)
for ENV_VAR in "${ENV_VARS[@]}"; do
    if [[ -z "$(eval "\$$ENV_VAR")" ]]; then
    echo "ERROR: This script is designed to be run from a \`chroot\` spawned by \`install-deb-distro.bash\`." >&2
    exit 4
    fi
done
unset ENV_VARS

echo ':: Declaring variables...'
## Misc local variables
KERNEL_COMMANDLINE=''

#######################################
##   R E C O N F I G U R E   F S H   ##
#######################################
echo ':: Modifying filesystem hierarchy...'

## This helps reflect dataset inheritance — filesystem `/root` lives under dataset `/home`.
if [[ ! -L '/home/root' ]]; then
    [[ ! -d '/root' ]] && mkdir '/root'
    ln -sTv '/root' '/home/root'
fi

## `/var/www` needs to be moved to `/srv` so that it is treated the same as other web services.
if [[ ! -L '/var/www' ]]; then
    [[ ! -d '/var/www' ]] && mkdir /var/www
    mv -f   '/var/www' '/srv/www' #FIXME: Will fail if `/srv/www` already exists; we need logic that merges the two directories.
    ln -sTv '/srv/www' '/var/www'
fi

## Some items in `/var` need to be tied to system snapshots.
## The criteria for inclusion is whether a rollback without the item would render the system's state inconsistent.
VARKEEP_DIR='/varlib'
mkdir -p "$VARKEEP_DIR"
if [[ -d "$VARKEEP_DIR" ]]; then
    declare -a VARKEEP_DIRS=('lib/apt' 'lib/dkms' 'lib/dpkg' 'lib/emacsen-common' 'lib/sgml-base' 'lib/ucf' 'lib/xml-core') # 'lib/apt/states' 'lib/shells'
    for DIR in "${VARKEEP_DIRS[@]}"; do
        if [[ ! -L "/var/$DIR" ]]; then
            [[ ! -d "/var/$DIR" ]] && mkdir "/var/$DIR"
            mv -f "/var/$DIR" "$VARKEEP_DIR/"
            ln -sTv "$VARKEEP_DIR/$DIR" "/var/$DIR"
        fi
    done
    declare -a VARKEEP_FILES=() #WARN: The following files' associated applications recreate them, meaning that any symlinks are be deleted and replaced: 'lib/apt/extended_states' 'lib/shells.state'
    for FILE in "${VARKEEP_FILES[@]}"; do
        if [[ ! -L "/var/$FILE" ]]; then
            [[ ! -f "/var/$FILE" ]] && continue
            install -D "/var/$FILE" "$VARKEEP_DIR/$FILE"
            rm -f "/var/$FILE"
            ln -sTv "$VARKEEP_DIR/$FILE" "/var/$FILE"
        fi
    done
fi
unset VARKEEP_DIR

###################################
##   C O N F I G U R E   A P T   ##
###################################

## Configure apt
echo ':: Configuring apt...'
case $DISTRO in
    1) cat > /etc/apt/sources.list <<EOF ;;
deb      https://deb.debian.org/debian/                $DEBIAN_VERSION                   main contrib non-free-firmware non-free
deb-src  https://deb.debian.org/debian/                $DEBIAN_VERSION                   main contrib non-free-firmware non-free

deb      https://deb.debian.org/debian/                $DEBIAN_VERSION-backports         main contrib non-free-firmware non-free
deb-src  https://deb.debian.org/debian/                $DEBIAN_VERSION-backports         main contrib non-free-firmware non-free

deb      https://deb.debian.org/debian/                $DEBIAN_VERSION-backports-sloppy  main contrib non-free-firmware non-free
deb-src  https://deb.debian.org/debian/                $DEBIAN_VERSION-backports-sloppy  main contrib non-free-firmware non-free

deb      https://security.debian.org/debian-security/  $DEBIAN_VERSION-security          main contrib non-free-firmware non-free
deb-src  https://security.debian.org/debian-security/  $DEBIAN_VERSION-security          main contrib non-free-firmware non-free

deb      https://deb.debian.org/debian/                $DEBIAN_VERSION-updates           main contrib non-free-firmware non-free
deb-src  https://deb.debian.org/debian/                $DEBIAN_VERSION-updates           main contrib non-free-firmware non-free
EOF
    2) cat > /etc/apt/sources.list.d/official-package-repositories.list <<EOF
deb https://archive.ubuntu.com/ubuntu/     $UBUNTU_VERSION            main restricted universe multiverse
#deb https://archive.canonical.com/ubuntu/ $UBUNTU_VERSION            partner
deb https://archive.ubuntu.com/ubuntu/     $UBUNTU_VERSION-updates    main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/     $UBUNTU_VERSION-backports  main restricted universe multiverse
deb https://security.ubuntu.com/ubuntu/    $UBUNTU_VERSION-security   main restricted universe multiverse
EOF
    set +e
    ${EDITOR:-nano} /etc/apt/sources.list.d/*
    set -e
    ;;
esac

## Get our packages up-to-date
echo ':: Upgrading packages...'
apt update
apt full-upgrade -y

## Enable automatic upgrades
echo ':: Automating upgrades...'
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

#################################################################
##   I N S T A L L   F U N D A M E N T A L   P A C K A G E S   ##
#################################################################

## Install build tools
echo ':: Installing build tools...'
apt install -y build-essential pkg-config

## Install Linux
echo ':: Installing Linux...'
case $DISTRO in
    1) apt install -y -t "$DEBIAN_VERSION-backports" linux-image-amd64 linux-headers-amd64 dkms ;;
    2) apt install -y -t "$UBUNTU_VERSION-backports" linux-image-generic linux-headers-generic dkms ;;
esac

## Install initramfs
echo ':: Installing initramfs...'
apt install -y initramfs-tools

## Install important but potentially missing compression algorithms and tooling
echo ':: Installing compressiony things...'
apt install -y gzip lz4 lzop unrar unzip zip zstd
idempotent_append 'lz4' '/etc/initramfs-tools/modules'
idempotent_append 'lz4_compress' '/etc/initramfs-tools/modules'

## Install systemd
echo ':: Installing systemd...'
apt install -y systemd

## Install MAC
echo ':: Enabling Mandatory Access Control...'
apt install -y apparmor apparmor-utils apparmor-notify apparmor-profiles apparmor-profiles-extra
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE apparmor=1 security=apparmor"

###########################################################
##   I N T E R A C T I V E   C O N F I G U R A T I O N   ##
###########################################################

## Configure hostname
echo ':: Configuring hostname...'
read -rp "What unqualified hostname would you like?: " HOSTNAME
# hostname "$HOSTNAME"
# hostname > '/etc/hostname'
hostnamectl set-hostname "$HOSTNAME"
sed -i '/^127\.0\.1\.1 /d' '/etc/hosts'
idempotent_append "127.0.1.1 $HOSTNAME" '/etc/hosts'

## Configure the system
echo ':: Configuring system...'
apt install -y locales
dpkg-reconfigure locales
apt install -y console-setup
read -rp "Note: 8x16 is considered kinda the standard size. Bold is easiest to read. VGA is probably your best bet. Press 'Enter' to continue. " _; unset _
dpkg-reconfigure console-setup
dpkg-reconfigure keyboard-configuration
dpkg-reconfigure tzdata

###################
##   U S E R S   ##
###################

## Set up /etc/skel
echo ':: Creating user configs...'
apt install -y tmux
echo 'set -g status-position top' > /etc/skel/.tmux.conf
idempotent_append 'shopt -q login_shell && [[ $- == *i* ]] && command -v tmux >/dev/null && [[ ! -n "$TMUX" ]] && exec tmux' '/etc/skel/.bashrc'

## Configure users
echo ':: Configuring users...'
if ! passwd -S root 2>/dev/null | grep -q ' P '; then
    echo 'Please enter a complex password for the root user: '
    passwd
fi
cp /etc/skel/. /root/
read -rp "Please enter a username for your personal user: " USERNAME
id "$USERNAME" >/dev/null 2>&1 || adduser "$USERNAME"
export USERNAME

###############
##   Z F S   ##
###############

## Install and configure ZFS
echo ':: Installing ZFS...'
case $DISTRO in
    1) apt install -y -t "$DEBIAN_VERSION-backports" zfsutils-linux zfs-dkms ;;
    2) apt install -y -t "$UBUNTU_VERSION-backports" zfsutils-linux ;;
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

## Configure trim/discard
echo ':: Scheduling trim...'
systemctl enable fstrim.timer ## Auto-trims everything in /etc/fstab
cat > /etc/systemd/system/zfstrim.service <<'EOF'
[Unit]
Description=Trim ZFS pools
After=zfs.target
[Service]
Type=oneshot
ExecStart=/usr/sbin/zpool trim -a
IOSchedulingClass=idle
EOF
cat > /etc/systemd/system/zfstrim.timer <<'EOF'
[Unit]
Description=Periodic ZFS trim
[Timer]
OnCalendar=*-*-* 03:00
Persistent=true
AccuracySec=1min
[Install]
WantedBy=timers.target
EOF
systemctl enable zfstrim.timer

###################################
##   M O U N T   O P T I O N S   ##
###################################

## Enforce mount options
echo ':: Changing default mount options...'
## ZFS does not provide properties for all of the mount options it supports (like `lazytime`; see https://github.com/openzfs/zfs/issues/9843), so we have to specify it manually when mounting datasets or monkeypatch `zfs` to do it by default.
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

cat > "$SCRIPT" <<'EOF'; chmod +x "$SCRIPT"
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

SCRIPT=/usr/local/sbin/mount
cat > "$SCRIPT" <<'EOF'; chmod +x "$SCRIPT"
#!/bin/sh
exec /usr/bin/mount -o noatime,lazytime "$@"
EOF
## Note to code reviewers: `-o` can be passed multiple times, and later values override prior ones.

SCRIPT=/usr/local/sbin/zfs
cat > "$SCRIPT" <<'EOF'; chmod +x "$SCRIPT"
#!/bin/sh
[ "$1" != mount ] && exec /usr/sbin/zfs "$@"
shift
exec /usr/sbin/zfs mount -o lazytime "$@"
EOF

unset BASENAME SCRIPT SERVICE

#################################################
##   E F I   S Y S T E M   P A R T I T I O N   ##
#################################################

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

#############################
##   S E C U R E B O O T   ##
#############################

## Set up SecureBoot
SBDIR='/etc/secureboot'
if efi-readvar -v PK | grep -q 'No PK present'; then

    ## Install dependencies
    echo ':: Installing SecureBoot dependencies...'
    apt install -y sbsigntool efitools openssl

    ## Set variables
    echo ':: Setting variables...'
    declare -a CERTS=('PK' 'KEK' 'db')
    declare -i SB_TTL_DAYS=7305 ## 20 years — comfortably longer than the maximum lifespan of any given machine, which ensures we never just randomly get locked-out of the system because some key expired.
    ## The Linux kernel supports modules using RSA-* (4096 by default), NIST P-384, SHA-{256,384,512}. (https://docs.kernel.org/admin-guide/module-signing.html).
    ## SecureBoot supports RSA-{2048,3072,4096}, NIST P-{256,384}, SHA-{256,384}. (https://uefi.org/specs/UEFI/2.10/32_Secure_Boot_and_Driver_Signing.html)
    ##     (In practice, though, not every SecureBoot implementation supports all of the possible algorithms.)
    ## We are using the same keys to handle both scenarios, so we are restricted to using only those algorithms which are supported by both the kernel and by SecureBoot.
    ## The overlapping algorithms are RSA-{2048,3072,4096}, NIST P-384, SHA-{256,384}.
    ##
    ## In terms of effective security, not one of the above algorithms will be crackable this century, which means they all provide identical lifetime security, which means:
    ## * We can mix-and-match keys to digests freely without worrying about weakening the overall model.
    ## * We should choose the smallest supported numbers, as they require the least amount of space and time.
    ## That whittles our effective options to just two:
    ## A. NIST P-384 + SHA-256 (best performance)
    ## B. RSA-2048 + SHA-256 (most compatibility)
    SB_ALGORITHM_CLASS='performance'
    declare -a SB_ALGORITHM_PARAMS=()
    SB_DIGEST_PARAM=''
    case "$SB_ALGORITHM_CLASS" in
        performance)
            SB_ALGORITHM_PARAMS=(
                -algorithm EC
                -pkeyopt ec_paramgen_curve:prime384v1
                -pkeyopt ec_param_enc:named_curve
            )
            SB_DIGEST_PARAM='-sha256'
            ;;
        compatibility)
            SB_ALGORITHM_PARAMS=(
                -algorithm RSA
                -pkeyopt rsa_keygen_bits:2048
            )
            SB_DIGEST_PARAM='-sha256'
            ;;
        *) exit 10
    esac
    unset SB_ALGORITHM_CLASS

    ## Create the directories
    echo ':: Creating directories...'
    install -m 755 -d "$SBDIR"
    cd "$SBDIR"
    install -m 755 -d 'auth' 'crt' 'csr' 'esl' 'uuid'
    install -m 700 -d 'key'

    ## Generate the keys.
    echo ':: Generating SecureBoot keys...'
    for CERT in "${CERTS[@]}"; do
        openssl genpkey "${SB_ALGORITHM_PARAMS[@]}" -out "key/$CERT.key"
    done
    unset SB_ALGORITHM_PARAMS

    ## Generate the certificates
    echo ':: Generating SecureBoot certificates...'
    ## PK
    openssl req -new -x509 \
        -key 'key/PK.key' \
        -out 'crt/PK.crt' \
        -subj '/CN=PK/' \
        -addext 'subjectAltName=URI:urn:secureboot:PK' \
        -addext 'authorityKeyIdentifier=keyid:always' \
        -addext 'subjectKeyIdentifier=hash' \
        -addext 'basicConstraints=critical,CA:TRUE,pathlen:1' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' \
        -days $SB_TTL_DAYS \
        "$SB_DIGEST_PARAM"
    ## KEK
    openssl req -new \
        -key  'key/KEK.key' \
        -out  'csr/KEK.csr' \
        -subj '/CN=KEK/'
    openssl x509 -req \
        -in    'csr/KEK.csr' \
        -out   'crt/KEK.crt' \
        -CA    'crt/PK.crt'  \
        -CAkey 'key/PK.key'  \
        -set_serial 0x$(openssl rand -hex 16) \
        -addext 'subjectAltName=URI:urn:secureboot:KEK' \
        -addext 'authorityKeyIdentifier=keyid,issuer:always' \
        -addext 'subjectKeyIdentifier=hash' \
        -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
        -addext 'keyUsage=critical,digitalSignature,keyCertSign,cRLSign' \
        -days $SB_TTL_DAYS \
        "$SB_DIGEST_PARAM"
    ## db
    openssl req -new \
        -key  'key/db.key' \
        -out  'csr/db.csr' \
        -subj '/CN=db/'
    openssl x509 -req \
        -in    'csr/db.csr'  \
        -out   'crt/db.crt'  \
        -CA    'crt/KEK.crt' \
        -CAkey 'key/KEK.key' \
        -set_serial 0x$(openssl rand -hex 16) \
        -addext 'subjectAltName=URI:urn:secureboot:db' \
        -addext 'authorityKeyIdentifier=keyid,issuer:always' \
        -addext 'subjectKeyIdentifier=hash' \
        -addext 'basicConstraints=critical,CA:FALSE' \
        -addext 'keyUsage=critical,digitalSignature' \
        -addext 'extendedKeyUsage=codeSigning' \
        -days $SB_TTL_DAYS \
        "$SB_DIGEST_PARAM"
    ## Verify
    openssl verify 'crt/db.crt' \
        -CAfile    'crt/PK.crt' \
        -untrusted 'crt/KEK.crt'

    ## Cleanup
    unset SB_TTL_DAYS SB_DIGEST_PARAM

    ## Send to UEFI
    echo ':: Configuring SecureBoot...'
    for CERT in "${CERTS[@]}"; do
        uuidgen > "uuid/$CERT.uuid"
        cert-to-efi-sig-list -g "$(cat "uuid/$CERT.uuid")" "crt/$CERT.crt" "esl/$CERT.esl"
    done
    sign-efi-sig-list -k "key/PK.key"  -c "crt/PK.crt"  PK  "esl/PK.esl"  "auth/PK.auth"
    sign-efi-sig-list -k "key/PK.key"  -c "crt/PK.crt"  KEK "esl/KEK.esl" "auth/KEK.auth"
    sign-efi-sig-list -k "key/KEK.key" -c "crt/KEK.crt" db  "esl/db.esl"  "auth/db.auth"
    chmod 0644 "uuid/"* "crt/"* "esl/"* "auth/"*

    ## Enroll the keys
    echo ':: Enrolling SecureBoot keys...'
    test -d /sys/firmware/efi && echo "UEFI OK" || echo "UEFI NOT OKAY"
    for CERT in "${CERTS[@]}"; do
        efi-updatevar -f "esl/$CERT.esl" "$CERT"
        efi-readvar -v "$CERT"
    done
    unset CERTS
    echo "INFO: To update your BIOS's SecureBoot database, you will have to append to the 'DB.esl' file, sign it as a 'DB.auth' file, and run \`efi-updatevar -f $SBDIR/auth/db.auth db\`."
    cd "$CWD"
else
    echo ':: Setting up SecureBoot...'
    echo "WARN: SecureBoot not in Setup Mode; may be unable to proceed."
fi

## Add support for SecureBoot to DKMS
echo ':: Configuring DKMS for SecureBoot...'
## Checking module signatures helps protect against the following: evil maid, root hack persistence, poisoned upstream package.
## #1 is eliminated by not storing the kernel in unencrypted /boot.
## #2 is, largely, too little too late — they already have root! And to get this kind of protection, I'd have to store the private key off-system, which would kill automation.
## #3 is *virtually* eliminated by package integrity checks, and it requires using upstream signatures (which I'm explicitly not doing).
## Accordingly, in this situation, there is no meaningful benefit to enforcing module signatures.
## But we might as well do so anyway.
## It's worth noting that, for this to work, the kernel must be built accepting `.platform` (UEFI-provided) keys. This is almost all kernels.
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE module.sig_enforce=1"
cat > /usr/local/sbin/dkms-sign-file <<'EOF'; chmod +x '/usr/local/sbin/dkms-sign-file'
#!/bin/sh
set -euo pipefail
SIGN_FILE=$(ls -1 /usr/lib/linux-kbuild-*/scripts/sign-file 2>/dev/null | sort -V | tail -n 1)
[ -x "$SIGN_FILE" ] || exit 1
exec "$SIGN_FILE" "$@"
EOF
FWCONF='/etc/dkms/framework.conf'
idempotent_append 'sign_tool="/usr/local/sbin/dkms-sign-file"' "$FWCONF"
idempotent_append "private_key=\"$SBDIR/key/db.key\"" "$FWCONF"
idempotent_append "public_key=\"$SBDIR/crt/db.crt\"" "$FWCONF"
unset FWCONF
dkms autoinstall --force
modinfo zfs | grep -E 'signer|sig_key|sig_hashalgo'

## Make ZBM work with SecureBoot
echo ':: Configuring ZBM for SecureBoot...'
cat > /etc/zfsbootmenu/generate-zbm.post.d/98-sign-efi.sh <<EOF ; chmod +x '/etc/zfsbootmenu/generate-zbm.post.d/98-sign-efi.sh'
#!/bin/sh
set -e
KEY_FILE=$SBDIR/key/db.key
CRT_FILE=$SBDIR/crt/db.crt
EFI_DIR=$ZBM_EFI_DIR
[ -s "\$KEY_FILE" -a -s "\$CRT_FILE" ] || exit 1
openssl pkey -in "\$KEY_FILE" -check -noout >/dev/null 2>&1 || exit 2
for EFI_FILE in "\$EFI_DIR"/*.EFI; do
    [ -s "\$EFI_FILE" ] || continue
    sbsign --output "\$EFI_FILE.signed" --key "\$KEY_FILE" --cert "\$CRT_FILE" "\$EFI_FILE" &&\\
    mv -f "\$EFI_FILE.signed" "\$EFI_FILE"
done
EOF
generate-zbm
sbverify --list /boot/esp/EFI/ZBM/*.EFI
sbverify --list /boot/esp/EFI/BOOT/BOOTX64.EFI

## Cleanup
unset SBDIR ZBM_EFI_DIR

###################################
##   M E M O R Y   M O U N T S   ##
###################################

## Configure swap
echo ':: Configuring swap...'
## Putting live swap on ZFS is *very* fraught; don't do it!
## Using a swap partition is a permanent loss of disk space, and there is much complexity involved because it must be encrypted — that means mdadm and LUKS beneath it.
## Swapping to zram (a compressed RAMdisk) is by *far* the simplest solution *and* its size is dynamic according to need, but it cannot be hibernated to.
## Hibernation support can be re-added by creating a temporary swap zvol when hibernation is requested, and removing it after resuming.
## (In principle, because this swap zvol's size is dynamically allocated according to current memory usage, this actually gives a stronger guarantee of being able to hibernate than many fixed-size swap partitions.)
## Because RAM is not plentiful, we want to compress swap so that we can store as much as possible; but high compression has a non-negligible cost when swapping in and out frequently.
## zswap is an optional intermediate cache between RAM and the actual swap device, with its own compression settings.
## When enabled, zswap contains things which were recently swapped-out, and so are most-likely to be swapped back in; while the zram then holds stuff that has been cold for a long time.
## This situation allows us to use heavier compression for the zram for maximum swap size, without risking a corresponding performance hit during swap thrashing.
## For zswap, then, we want to use the lightest reasonable compression algorithm.
## The main downside is that, when things move from zswap to the zram, they must first be decompressed before being recompressed. That's not a big deal, though, since only particularly cold pages should ever make it to the zram.
## We need to leave enough free RAM to where the system does not experience memory pressure (which becomes a serious problem around *roughly* 80% utilization).
## 50% is about the highest reasonable for zswap + zram, since that allows 30% for normal system use when factoring that the last 20% are pressured. (Of course, the exact percents that make sense do depend somewhat on absolute system memory and idle workload.)
## With 50% dedication, a 1:2 ratio of zswap:zram keeps us close to the default values for each. That's 16.67% for zswap, and 33.33% for the zram.
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE zswap.enabled=1 zswap.max_pool_percent=17 zswap.compressor=lz4" #NOTE: Fractional percents (eg, `12.5`) are not possible.
apt install -y systemd-zram-generator
cat > /etc/systemd/zram-generator.conf <<'EOF'
## zram swap
[zram0]
zram-size = ram / 3
#TODO: Tune compression level.
compression-algorithm = zstd(level=2)
## Priority should be maxed, to help avoid slower devices becoming preferred.
swap-priority = 32767

## /tmp
## * Vanilla tmpfs can swap (especially if it doesn't have a limit), so its stale files are *already* compressed via zswap + zram swap.
## * Compression DRAMATICALLY slows RAM.
## Given the above two considerations, `/tmp` on zram is quite unwise.

## /run
## This is mounted as tmpfs extremely early, before generators run; consequently, it is not possible to use zram for it (at least not in *this* way).

## Example general-purpose zram device
# [zram1]
# zram-size = 1G
# compression-algorithm = lz4
# fs-type = ext4
## Enable `metadata_csum` if you don’t trust your RAM.
# fs-create-options = "-E lazy_itable_init=0,lazy_journal_init=0 -m0 -O none,extent,dir_index,extra_isize=256 -T small"
## No point in `lazytime` when the filesystem is in RAM.
# options = noatime,discard
## Yes, this should generate and mount before anything needs it.
# mount-point = /foo
EOF
# systemctl daemon-reload ## Shouldn't run from chroot.
# systemctl start systemd-zram-setup@zram0 ## Shouldn't start/stop from chroot.

## Configure `/tmp` as tmpfs
echo ':: Configuring `/tmp`...'
cp /usr/share/systemd/tmp.mount /etc/systemd/system/
systemctl enable tmp.mount
mkdir -p /etc/systemd/system/tmp.mount.d
cat > /etc/systemd/system/tmp.mount.d/override.conf <<'EOF'
[Mount]
Options=mode=1777,nosuid,nodev,size=5G,noatime
## 5G is enough space to have 1G free while extracting a 4G archive (the max supported by FAT32). 1G is plenty for normal operation. ## No point in `lazytime` when the filesystem is in RAM.
EOF
mkdir -p /etc/systemd/system/console-setup.service.d
cat > /etc/systemd/system/console-setup.service.d/override.conf <<'EOF' #BUG: Resolves an upstream issue where console-setup can happen shortly before tmpfs mounts and accordingly fail when tmpfs effectively deletes /tmp while console-setup is happening.
[Unit]
# Requires=tmp.mount
After=tmp.mount
EOF
# systemctl daemon-reload ## Shouldn't run from chroot.
## Because swap is now in memory, the kernel's usual assumption that swap is slow has been made false. We need to let the kernel know.
idempotent_append 'vm.swappiness=134' '/etc/sysctl.d/62-io-tweakable.conf' ## This value is a preference ratio of 2:1::cache:anon, which is the inverse of the default 1:2::cache:anon ratio.

###############################
##   H I B E R N A T I O N   ##
###############################

#TODO: Enable hibernation
##
## Right before hibernation happens, we create a new sparse zvol with compression enabled. It always has the same name/path.
## We then format it as a sparse swap partition equal to total RAM. It always has the same UUID.
## We set its priority to the absolute minimum (-1) so that no live data is ever sent there.
## Then we hibernate to it.
##
## initramfs needs to be told to unhibernate from this zvol swap. This must happen immediately after it unlocks the pool(s).
## After the system is fully restored, we delete the zvol.
## We also delete the zvol on normal boots (and log a warning), just in case anything ever goes wrong and a dead zvol swap is ever somehow left behind.

#TODO: Enable automatic hibernation when NUT detects that the UPS is low on battery.

#########################
##   P A C K A G E S   ##
#########################

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
apt install -y linux-tools-common "linux-tools-$KVER" i2c-tools ethtool fancontrol lm-sensors lshw net-tools pciutils read-edid smartmontools hdparm tpm2-tools usbutils sysstat iotop dmsetup numactl numatop procps psmisc cgroup-tools mesa-utils clinfo nvme-cli
unset KVER
sensors-detect --auto

## Install applications
echo ':: Installing applications...'
## Applications that need configuration
[[ $DISTRO -eq 1 ]] && tasksel --new-install
apt install -y popularity-contest
## Common applications
apt install -y cups rsync
## Niche applications
# apt install -y # sanoid

#############################
##   N E T W O R K I N G   ##
#############################

echo ':: Configuring networking...'

## Configure WOL
read -rp 'Enter "y" to enable Wake-On-LAN, or "n" to leave it disabled. ' DO_IT
if [[ "$DO_IT" == 'y' ]]; then
    cat > /etc/udev/rules.d/99-wol.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="net", KERNEL=="en*", RUN+="/usr/sbin/ethtool -s %k wol g"
ACTION=="add", SUBSYSTEM=="net", KERNEL=="eth*", RUN+="/usr/sbin/ethtool -s %k wol g"
EOF
fi; unset DO_IT

## Set up `ssh`
read -rp 'Enter "y" to enable ssh, or "n" to leave it disabled. ' DO_IT
if [[ "$DO_IT" == 'y' ]]; then
    apt install -y openssh-server
    sed -Ei 's/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    systemctl enable ssh
fi; unset DO_IT

echo ':: Configuring Wi-Fi...'

## Configure regulatory domain
read -rp 'Please enter your wireless regulatory domain: ("US" for the USA) ' REGDOM
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE cfg80211.ieee80211_regdom=$REGDOM"
unset REGDOM

## Disable Wi-Fi
read -rp 'Enter "y" to disable Wi-Fi or "n" to leave it untouched. ' DO_IT
if [[ "$DO_IT" == 'y' ]]; then
    apt install -y rfkill
    cat > /etc/udev/rules.d/80-rfkill-wifi.rules <<'EOF'
SUBSYSTEM=="rfkill", ATTR{type}=="wlan", ACTION=="add|change", RUN+="/usr/sbin/rfkill block wifi"
EOF
fi; unset DO_IT

#################
##   T I M E   ##
#################

#TODO: Configure Chrony

#######################
##   T H E M I N G   ##
#######################

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

#######################################
##   T T Y   A S S I G N M E N T S   ##
#######################################
echo ':: Assigning TTYs...'

## Put the host console at 10.
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE console=10"

## Script that attaches guest VM consoles to arbitrary TTYs.
SCRIPT='/usr/local/bin/vm-to-tty'; cat > "$SCRIPT" <<'EOF' && chmod 755 "$SCRIPT"; unset SCRIPT
#!/bin/dash
set -eu
if [ $# -ne 2 ]; then
    echo 'Usage: `vm-to-tty vm_name tty_number`' >&2
    exit 1
fi
VM="$1"; TTY="$2"
shift 2
clear
while true; do
    PTS=$(virsh ttyconsole "$VM" 2>/dev/null || true)
    if [ -n "$PTS" ] && [ -e "$PTS" ]; then
        exec socat "/dev/tty$TTY",raw,echo=0 "$PTS",raw,echo=0
    fi
    sleep 1
done
EOF

## Service that automates the running of that script.
cat > '/etc/systemd/system/vm-to-tty@.service' <<'EOF'
[Unit]
Description=Assign a VM's serial console to a TTY (%i)
Requires=libvirtd.service
After=libvirtd.service libvirt-guests.service
[Service]
ExecStart=/bin/sh -c '/usr/local/bin/vm-to-tty "${1%%:*}" "${1##*:}"' sh %i
Restart=always
RestartSec=1
StandardInput=null
StandardOutput=null
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
# systemctl daemon-reload ## Shouldn't run from chroot.

## The idea is that VMs' serial consoles can own all TTYs higher than 10.

###################
##   S I Z E S   ##
###################

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

## Limit log size
echo ':: Limiting log sizes...'
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/max-size.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=256M
RuntimeMaxUse=128M
EOF

#########################################################
##   A D D I T I O N A L   C O N F I G U R A T I O N   ##
#########################################################

## Sysctl
echo ':: Configuring sysctl...'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/61-io-static.conf
idempotent_append 'vm.legacy_va_layout=0'            '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'kernel.io_delay_type=2'           '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.compact_unevictable_allowed=0' '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.oom_kill_allocating_task=0'    '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.overcommit_memory=0'           '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.overcommit_ratio=80'           '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.memory_failure_recovery=1'     '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.memory_failure_early_kill=1'   '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.laptop_mode=0'                 '/etc/sysctl.d/961-io-static.conf'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/62-io-tweakable.conf
idempotent_append 'vm.zone_reclaim_mode=0'          '/etc/sysctl.d/62-io-tweakable.conf'
#NOTE: `vm.swappiness` was set in the "S W A P" section of this file.
idempotent_append 'vm.vfs_cache_pressure=50'        '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'vm.vfs_cache_pressure_denom=100' '/etc/sysctl.d/62-io-tweakable.conf'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/68-debug.conf
idempotent_append 'net.ipv4.icmp_errors_use_inbound_ifaddr=1'    '/etc/sysctl.d/968-debug.conf'
idempotent_append 'net.ipv4.icmp_ignore_bogus_error_responses=1' '/etc/sysctl.d/968-debug.conf'
idempotent_append 'net.ipv4.conf.all.log_martians=1'             '/etc/sysctl.d/968-debug.conf'
idempotent_append 'vm.block_dump=0'                              '/etc/sysctl.d/968-debug.conf'
idempotent_append 'vm.oom_dump_tasks=0'                          '/etc/sysctl.d/968-debug.conf'
idempotent_append 'vm.stat_interval=1'                           '/etc/sysctl.d/968-debug.conf'
idempotent_append 'vm.panic_on_oom=0'                            '/etc/sysctl.d/968-debug.conf'
idempotent_append 'kernel.printk = 3 5 2 3'                      '/etc/sysctl.d/968-debug.conf'
idempotent_append 'vm.mem_profiling=0'                           '/etc/sysctl.d/968-debug.conf'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/69-security.conf
idempotent_append 'kernel.dmesg_restrict=1'    '/etc/sysctl.d/969-security.conf'
idempotent_append 'kernel.kptr_restrict=1'     '/etc/sysctl.d/969-security.conf'
idempotent_append 'kernel.yama.ptrace_scope=1' '/etc/sysctl.d/969-security.conf'
idempotent_append 'vm.mmap_min_addr=65536'     '/etc/sysctl.d/969-security.conf'
idempotent_append 'fs.protected_fifos = 1'     '/etc/sysctl.d/969-security.conf'
idempotent_append 'fs.protected_hardlinks = 1' '/etc/sysctl.d/969-security.conf'
idempotent_append 'fs.protected_regular = 2'   '/etc/sysctl.d/969-security.conf'
idempotent_append 'fs.protected_symlinks = 1'  '/etc/sysctl.d/969-security.conf'
sysctl --system

echo ':: Additional configurations...'
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE page_alloc.shuffle=1" ## Easy but small security win.

## Set kernel commandline
echo ':: Setting kernel commandline...'
mkdir -p "$ENV_KERNEL_COMMANDLINE_DIR"
echo "$KERNEL_COMMANDLINE" > "$ENV_KERNEL_COMMANDLINE_DIR/commandline.txt"
echo '#!/bin/sh' > "$ENV_KERNEL_COMMANDLINE_DIR/set-commandline"
echo 'BOOTFS=$(zpool get -Ho value bootfs '"$ENV_POOL_NAME_OS"')' > "$ENV_KERNEL_COMMANDLINE_DIR/set-commandline"
cat >> "$ENV_KERNEL_COMMANDLINE_DIR/set-commandline" <<'EOF'
COMMANDLINE="$(awk '{for(i=1;i<=NF;i++){t=$i;if(index(t,"=")){split(t,a,"=");m[a[1]]=t}else m[t]=t}}END{for(k in m)printf "%s ",m[k]}' /etc/zfsbootmenu/commandline/commandline.txt)" ## AI code that deduplicates like keys, keeping the rightmost instances.
zfs set org.zfsbootmenu:commandline="$COMMANDLINE" "$BOOTFS"
zfs get org.zfsbootmenu:commandline "$BOOTFS"
EOF
export ENV_KERNEL_COMMANDLINE_DIR
"$ENV_KERNEL_COMMANDLINE_DIR/set-commandline"
update-initramfs -u

###################
##   O U T R O   ##
###################

## Wrap up
echo ':: Creating snapshot...'
set +e
zfs snapshot -r "$ENV_POOL_NAME_OS@install-$DISTRO"
set -e

## Done
echo ':: Done.'
case "$HOSTNAME" in
    'aetherius'|'morpheus'|'duat') echo "To continue installation, reboot and then execute \`./configure-$HOSTNAME.bash\`." ;;
    *) echo "WARN: Unsupported hostname: '$HOSTNAME'" ;;
esac
exit 0
