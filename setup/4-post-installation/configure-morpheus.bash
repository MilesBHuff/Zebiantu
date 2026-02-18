#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob
function helptext {
    echo "Usage: configure-morpheus.bash"
    echo
    echo 'This is a one-shot script that finishes setting up Morpheus (using Ubuntu).'
    echo 'Morpheus is an AI inference server running on a maxed-out Framework Desktop.'
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
    UBUNTU_VERSION \
    USERNAME \
    ENV_KERNEL_COMMANDLINE_DIR

echo ':: Declaring variables...'
## Misc local variables
KERNEL_COMMANDLINE="$(xargs < "$ENV_KERNEL_COMMANDLINE_DIR/commandline.txt")"

#####################################
##   I N I T I A L   C O N F I G   ##
#####################################

echo ':: Installing base system...'
apt install -y ubuntu-server
apt install -y ubuntu-desktop-minimal

echo ':: Disable DE by default...'
systemctl set-default multi-user.target
# systemctl mask graphical.target
systemctl disable gdm3

echo ':: Switching to NetworkManager from networkd...'
apt install -y networkmanager ## Just to be safe; should have already installed with the above.
mkdir -p /etc/netplan ## Just to be safe.
cat > /etc/netplan/99-use-networkmanager.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
EOF
systemctl stop systemd-networkd
systemctl start NetworkManager
netplan apply
systemctl enable NetworkManager
systemctl disable systemd-networkd
# systemctl mask systemd-networkd
# apt purge systemd-networkd ## Also removes the `ubuntu-server` metapackage, which is not a desirable outcome.

echo ':: Disabling Wi-Fi...'
nmcli radio wifi off
nmcli general reload

echo ':: Installing system-specific things...'
## Daemons
apt install -y nut-client
systemctl enable nut-client
## Drivers
apt install -y amd64-microcode firmware-amd-graphics firmware-realtek
## Controllers
apt install -y -t "$UBUNTU_VERSION-backports" openrgb

#########################################
##   C O N F I G U R E   F O R   A I   ##
#########################################

## Configure CPU features
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE amd_iommu=on iommu=pt"
cat > /etc/modprobe.d/kvm-amd.conf <<EOF
options kvm-amd nested=1
EOF

echo ':: Setting up audio codecs...'
apt install -y sox ffmpeg

echo ':: Setting up Python...'
apt install -y python3-venv python3-pip

echo ':: Setting up OCR...'
apt install -y tesseract-ocr #NOTE: This only does English; es posible que en el futuro necesitará otros.

echo ':: Setting up Docker...'
apt install -y docker.io
systemctl enable docker
systemctl start docker
# usermod -aG docker "$USERNAME" ## Docker is rootish; might be better to require using `sudo` than to add users to the group.
while ! systemctl is-active --quiet docker; do
    sleep 1
done

echo ':: Setting up ROCm...'
apt install -y wget gnupg2 ca-certificates
wget -qO - https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor | tee /usr/share/keyrings/rocm.gpg > /dev/null
ROCM_VERSION=latest
ROCM_DISTRO=noble #TODO: Change once support lands for Resolute Racoon (26.04).
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/$ROCM_VERSION/Dists/$ROCM_DISTRO $ROCM_DISTRO main" > /etc/apt/sources.list.d/rocm.list
apt update
apt install -y rocm-core rocm-hip-runtime rocm-opencl-runtime rocminfo
usermod -aG video,render "$USERNAME"

echo ':: Testing ROCm...'
sudo -u "$USERNAME" rocminfo || echo "ROCm failed to initialize; check kernel/firmware compatibility." >&2
docker run --rm \
    --device=/dev/kfd \
    --device=/dev/dri \
    --group-add video \
    --group-add render \
    rocm/rocm-terminal \
    rocminfo ||\
    echo "Docker ROCm failed to initialize; check kernel/firmware compatibility." >&2

echo ':: Setting up directories...'
AI_DIR=/srv/ai
mkdir -p "$AI_DIR"
chown -R "$USERNAME" "$AI_DIR"

#################################
##   P O W E R   O N / O F F   ##
#################################

systemctl enable nightly-reboot.timer ## We need to restart daily because this box does not have ECC.

#############################
##   S C H E D U L I N G   ##
#############################
#TODO: Get drive WWN IDs (`/dev/disk/by-id/`).

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

reschedule-timer "zfs-scrub@$ENV_ZPOOL_NAME_OS.timer" '*-*-1 1:00'          '10m' '0'
# reschedule-timer 'smart-short@.timer'               '*-*-7,14,21,28 0:00' '10m' '0' #TODO: Get drive WWN (`/dev/disk/by-id/`).
# reschedule-timer 'smart-short@.timer'               '*-*-7,14,21,28 0:00' '10m' '0' #TODO: Get drive WWN (`/dev/disk/by-id/`).
reschedule-timer 'fstrim.timer'                       '*-*-7,14,21,28 2:00' '10m' '0'
reschedule-timer 'zfstrim.timer'                      '*-*-7,14,21,28 2:00' '10m' '0'
reschedule-timer 'reboot.timer'                       '*-*-* 5:00'          '10m' '0'

systemctl daemon-reload

#########################################################
##   A D D I T I O N A L   C O N F I G U R A T I O N   ##
#########################################################

## Sysctl
echo ':: Configuring sysctl...'
idempotent_append 'vm.max_map_count=1048576'           '/etc/sysctl.d/99-ai.conf'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/62-io-tweakable.conf
sed -iE           's/^(vm\.swappiness)=[0-9]+$/\1=84/' '/etc/sysctl.d/62-io-tweakable.conf' ## AI-estimated per Morpheus's specific hardware and the formula given in `mem-fs.bash`.
idempotent_append 'kernel.mm.ksm.run=0'                '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'kernel.mm.ksm.pages_to_scan=100'    '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'kernel.mm.ksm.sleep_millisecs=1000' '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'vm.dirty_writeback_centisecs=500'   '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'vm.dirty_expire_centisecs=1500'     '/etc/sysctl.d/62-io-tweakable.conf'
sysctl --system

## Set kernel commandline
echo "$KERNEL_COMMANDLINE" > "$ENV_KERNEL_COMMANDLINE_DIR/commandline.txt"
"$ENV_KERNEL_COMMANDLINE_DIR/set-commandline" ## Sorts, deduplicates, and saves the new commandline.
update-initramfs -u

###################
##   O U T R O   ##
###################

## Wrap up
echo ':: Creating snapshot...'
set +e
zfs snapshot -r "$ENV_POOL_NAME_OS@install-morpheus"
set -e

## Done
echo ':: Done.'
exit 0
