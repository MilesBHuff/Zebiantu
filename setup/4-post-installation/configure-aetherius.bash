#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob
function helptext {
    echo "Usage: configure-aetherius.bash"
    echo
    echo 'This is a one-shot script that finishes setting up Aetherius (using Debian).'
    echo 'Aetherius is a NAS and home server running on a custom-built computer.'
}
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

echo ':: Getting environment...'
## Load and validate environment variables
load_envfile "$ROOT_DIR/setup-env.sh" \
    ENV_FILESYSTEM_ENVFILE \
    ENV_SETUP_ENVFILE
load_envfile "$ENV_FILESYSTEM_ENVFILE" \
    ENV_POOL_NAME_OS
load_envfile "$ENV_SETUP_ENVFILE" \
    DEBIAN_VERSION \
    ENV_KERNEL_COMMANDLINE_DIR

echo ':: Declaring variables...'
## Misc local variables
KERNEL_COMMANDLINE="$(xargs < "$ENV_KERNEL_COMMANDLINE_DIR/commandline.txt")"

#####################################
##   I N I T I A L   C O N F I G   ##
#####################################

## Configure network
echo ':: Configuring network...'
ip addr show
read -rp "Copy the interface name you want to use, and paste it here; then press 'Enter': " INTERFACE_NAME #TODO: Automate this.
cat > "/etc/network/interfaces.d/$INTERFACE_NAME.conf" <<EOF
auto $INTERFACE_NAME
iface $INTERFACE_NAME inet dhcp
EOF

echo ':: Installing system-specific things...'
## Daemons
apt install -y nut-server
systemctl enable nut-server
systemctl enable nut-monitor
## Drivers
apt install -y amd64-microcode firmware-amd-graphics firmware-mellanox firmware-realtek
## Filesystems
apt install -y btrfs-progs e2fsprogs ntfs-3g
## Tools
apt install -y ipmitool openseachest photorec testdisk wipefs
## Controllers
apt install -y -t "$DEBIAN_VERSION-backports" openrgb

#################################################
##   P R O P R I E T A R Y   S O F T W A R E   ##
#################################################

## Install STORCLI 3.5 P34
if [[ ! -d '/opt/MegaRAID/storcli' ]]; then
    read -rp 'After you have downloaded and extracted STORCLI to the appropriate directory in this repo, press "Enter". ' _; unset _
    cd "$ROOT_DIR/software/STORCLI/Ubuntu"
    ./install.sh
fi

## Install SAS3FLASH (necessary for self-signing the UEFI ROM)
if [[ ! -d '/opt/MegaRAID/installer' ]]; then
    read -rp 'After you have downloaded and extracted SAS3FLASH and SAS3IRCU to the appropriate directory in this repo, press "Enter". ' _; unset _
    cd "$ROOT_DIR/software/SAS3FLASH"
    ./install.sh
fi

## Install Mellanox stuff
## Special thanks to [Nilson Lopes](https://gist.github.com/noslin005/b0d315c814cd1cb37a7aafdae5df4ef0) and ChatGPT for helping with this section.
SOURCES_FILE='/etc/apt/sources.list.d/ofed.list'
if [[ ! -f "$SOURCES_FILE" ]]; then
    OFED_VERSION='latest'
    DISTRO_VERSION='Debian12.5' #FIXME: We're on Debian 13 Trixie, but Nvidia hasn't shipped for that yet.
    SOURCES_FILE='/etc/apt/sources.list.d/ofed.list'
    KEYRING='/usr/share/keyrings/ofed.gpg'
    wget -qO- 'https://www.mellanox.com/downloads/ofed/RPM-GPG-KEY-Mellanox' | gpg --dearmor > "$KEYRING"
    chmod 644 "$KEYRING"
    cat > "$SOURCES_FILE" <<EOF
deb [signed-by=$KEYRING] https://linux.mellanox.com/public/repo/mlnx_ofed/$OFED_VERSION/$DISTRO_VERSION/x86_64 ./
EOF
    chmod 644 "$SOURCES_FILE"
    unset KEYRING OFED_VERSION DISTRO_VERSION SOURCES_FILE
    apt update
    apt install -y mft mlnx-fw-updater mlnx-tools mlnx-ethtool

    ## Only install MFT's DKMS extension if our system can't talk to our Mellanox card natively.
    if ! mlxconfig -d "$(lspci -Dn | awk '/15b3/ {print $1; exit}')" q >/dev/null 2>&1; then #AI #WARN: Only checks the first Mellanox card. That's fine for this server, because we only have the one.
        apt install -y kernel-mft-dkms
        systemctl enable --now mst
    fi
fi

## Install Supermicro BIOS tool
if [[ ! -f '/usr/local/sbin/ipmicfg' ]]; then
    cd "$ROOT_DIR/software/IPMICFG"
    ARCHIVE='IPMICFG.ZIP'
    SIG='IPMICFG.SIG'
    URL='https://www.supermicro.com/Bios/sw_download/965/IPMICFG_1.37.0_build.250723' ## Updated: 2025-08-13 | Checked: 2026-02-09
    set +e
    while true; do
        curl -fL "$URL.zip" -o "$ARCHIVE"
        curl -fL "$URL.sig" -o "$SIG"
        if gpg --verify "$SIG" "$ARCHIVE"; then #FIXME: There is no way to know that the sig and the archive weren't *both* MITM'd.
            break
        else
            read -rp 'Download failed; press "Enter" to try again. ' _ && unset _
        fi
    done
    set -e
    rm "$SIG"
    unset URL SIG
    unzip "$ARCHIVE"
    rm -f "$ARCHIVE"
    unset ARCHIVE
    mv IPMICFG_*/ ./
    rmdir IPMICFG_*/
    ./install.sh ## I wrote this script.
fi

## Done
cd "$CWD"

###############################
##   S E T   U P   T R N G   ##
###############################

## Set up TRNG
echo ':: Set up TRNG...'
#NOTE: This installs Debian's official version in order to pull in dependencies, and then overrides it with a locally-compiled version. (The one shipped with Debian as of 2025-06-12 (0.3.3) is missing a critical patch that tells that CPU to reseed. Without this, the extra entropy is mostly wasted.)
apt install -y infnoise
systemctl disable infnoise
# KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE random.trust_cpu=off" ## No need to use RDSEED/RDRAND when you have a trusted TRNG, with the exception of at early boot; then again, early boot is the only time this matters and the only time this TRNG isn't used, so... probably best to leave enabled.
apt install -y libftdi-dev
cd /usr/local/src
REPO='infnoise'
[[ ! -d "$REPO" ]] && git clone "https://github.com/leetronics/$REPO.git"
cd "$REPO/software"
make -f Makefile.linux
make -f Makefile.linux install
systemctl enable infnoise
mkdir -p /etc/systemd/system/infnoise.service.d
cat > /etc/systemd/system/infnoise.service.d/override.conf <<'EOF' ## The latest code does not utilize all of the arguments needed to properly utilize the TRNG with modern Linux kernels, so we have to write it out ourselves.
[Service]
ExecStart=
ExecStart=/usr/local/sbin/infnoise --daemon --pidfile=/var/run/infnoise.pid --dev-random --feed-frequency=30 --reseed-crng
EOF
systemctl daemon-reload
systemctl start infnoise

#############################
##   S C H E D U L I N G   ##
#############################
#TODO: Get drive WWNs (`/dev/disk/by-id/`).
echo ':: Scheduling tasks...'

function reschedule-timer {
    mkdir -p "/etc/systemd/system/$1.d"
    if ! systemd-analyze calendar "$2" >/dev/null 2>&1; then
        echo "$0: Invalid systemd calendar: '$2'. "
        return 1
    fi
    cat > "/etc/systemd/system/$1.d/schedule.conf" <<EOF
[Timer]
OnCalendar=$2
AccuracySec=$3
RandomizedDelaySec=$4
EOF
}

## SHORT SMART TESTS
## vdev HDDs (should take a modest amount of time)
# reschedule-timer 'smart-short@.timer' '*-*-12,26 0:00' '10m' '0'
# reschedule-timer 'smart-short@.timer' '*-*-13,27 0:00' '10m' '0'
# reschedule-timer 'smart-short@.timer' '*-*-14,28 0:00' '10m' '0'
## svdev SSDs (should finish quickly)
# reschedule-timer 'smart-short@.timer' '*-*-5,12,19,26 0:00' '10m' '0'
# reschedule-timer 'smart-short@.timer' '*-*-6,13,20,27 0:00' '10m' '0'
# reschedule-timer 'smart-short@.timer' '*-*-7,14,21,28 0:00' '10m' '0'
## OS SSDs (should finish quickly)
# reschedule-timer 'smart-short@.timer' '*-*-5,12,19,26 0:00' '10m' '0'
# reschedule-timer 'smart-short@.timer' '*-*-6,13,20,27 0:00' '10m' '0'
# reschedule-timer 'smart-short@.timer' '*-*-7,14,21,28 0:00' '10m' '0'
## L2ARC SSD (should finish quickly)
# reschedule-timer 'smart-short@.timer' '*-*-7,14,21,28 0:00' '10m' '0'

## TRIM/DISCARD (could take a couple hours)
reschedule-timer 'fstrim.timer'  '*-*-7,14,21,28 2:00' '10m' '0'
reschedule-timer 'zfstrim.timer' '*-*-7,14,21,28 2:00' '10m' '0'

## LONG SMART TESTS
## vdev HDDs (should take a couple days each)
# reschedule-timer 'smart-long@.timer' '*-1,5,9-1 1:00' '10m' '0'
# reschedule-timer 'smart-long@.timer' '*-1,5,9-4 1:00' '10m' '0'
# reschedule-timer 'smart-long@.timer' '*-1,5,9-7 1:00' '10m' '0'
## svdev SSDs (should finish quickly)
# reschedule-timer 'smart-long@.timer' '*-1,5,9-1 1:00' '10m' '0'
# reschedule-timer 'smart-long@.timer' '*-1,5,9-2 1:00' '10m' '0'
# reschedule-timer 'smart-long@.timer' '*-1,5,9-3 1:00' '10m' '0'
## OS SSDs (should finish quickly)
# reschedule-timer 'smart-long@.timer' '*-1,5,9-1 1:00' '10m' '0'
# reschedule-timer 'smart-long@.timer' '*-1,5,9-2 1:00' '10m' '0'
# reschedule-timer 'smart-long@.timer' '*-1,5,9-3 1:00' '10m' '0'

## SCRUBS (will take a long time)
reschedule-timer "zfs-scrub@$ENV_ZPOOL_NAME_OS.timer"  '*-3,7,11-1 1:00' '10m' '0' ## Will hopefully finish before dawn so that there aren't two scrubs running when people are accessing services.
reschedule-timer "zfs-scrub@$ENV_ZPOOL_NAME_NAS.timer" '*-3,7,11-1 1:00' '10m' '0'

## BACKUP MAINTENANCE
# reschedule-timer 'smart-short@.timer'                '*-*-15 1:00' '10m' '0'
reschedule-timer "zfs-scrub@$ENV_ZPOOL_NAME_DAS.timer" '*-*-1 3:00'  '10m' '0'

## DONE
systemctl daemon-reload

#########################################################
##   A D D I T I O N A L   C O N F I G U R A T I O N   ##
#########################################################
echo ':: Configuring miscellania...'

## Ensure that the NAS is snapshotted and the backup is not
cat >> '/etc/sanoid/sanoid.conf' <<EOF

## Backups are controlled by Syncoid, not by Sanoid.
[$ENV_POOL_NAME_DAS]
    use_template = none
[$ENV_POOL_NAME_NAS]
    use_template = min
EOF

## Configure CPU features
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE amd_iommu=on" ## Leaving `iommu=pt` off for security.
cat > /etc/modprobe.d/kvm-amd.conf <<'EOF'
options kvm-amd nested=1
EOF

## Set kernel commandline
echo "$KERNEL_COMMANDLINE" > "$ENV_KERNEL_COMMANDLINE_DIR/commandline.txt"
"$ENV_KERNEL_COMMANDLINE_DIR/set-commandline" ## Sorts, deduplicates, and saves the new commandline.
update-initramfs -u

## Sysctl
echo ':: Configuring sysctl...'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/62-io-tweakable.conf
sed -iE           's/^(vm\.swappiness)=[0-9]+$/\1=198/' '/etc/sysctl.d/62-io-tweakable.conf' ## AI-estimated per Aetherius's specific hardware, some moderately-relevant zstd compression benchmarks I ran, and the formula given in `mem-fs.bash`.
idempotent_append 'kernel.mm.ksm.run=1'                 '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'kernel.mm.ksm.pages_to_scan=100'     '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'kernel.mm.ksm.sleep_millisecs=1000'  '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'vm.dirty_writeback_centisecs=500'    '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'vm.dirty_expire_centisecs=1500'      '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'vm.dirty_bytes=1250000000'           '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'vm.dirty_background_bytes=625000000' '/etc/sysctl.d/62-io-tweakable.conf'
sysctl --system

###################
##   O U T R O   ##
###################

## Wrap up
echo ':: Creating snapshot...'
set +e
zfs snapshot -r "$ENV_POOL_NAME_OS@install-aetherius"
set -e

## Done
exec ./convert-debian-to-proxmox.bash
