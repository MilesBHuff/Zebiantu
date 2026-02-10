#!/usr/bin/env bash
set -euo pipefail

################################################################################
## META                                                                       ##
################################################################################

function helptext {
    echo "Usage: configure-morpheus.bash"
    echo
    echo 'This is a one-shot script that finishes setting up Morpheus (using Ubuntu).'
    echo 'Morpheus is an AI inference server running on a maxed-out Framework Desktop.'
}
## Special thanks to ChatGPT for helping with my endless questions.

################################################################################
## FUNCTIONS                                                                  ##
################################################################################
echo ':: Declaring functions...'

declare -a HELPERS=('../helpers/load_envfile.bash' '../helpers/idempotent_append.bash')
for HELPER in "${HELPERS[@]}"; do
    if [[ -x "$HELPER" ]]; then
        source "$HELPER"
    else
        echo "ERROR: Failed to load '$HELPER'." >&2
        exit 1
    fi
done

################################################################################
## ENVIRONMENT                                                                ##
################################################################################
echo ':: Getting environment...'

## Base paths
CWD=$(pwd)
ROOT_DIR="$CWD/../.."

## Load and validate environment variables
load_envfile "$ROOT_DIR/setup-env.sh" \
    "$ENV_FILESYSTEM_ENVFILE" \
    "$ENV_SETUP_ENVFILE"
load_envfile "$ENV_FILESYSTEM_ENVFILE" \
    "$ENV_POOL_NAME_OS"
load_envfile "$ENV_SETUP_ENVFILE" \
    "$UBUNTU_VERSION" \
    "$USERNAME" \
    "$ENV_KERNEL_COMMANDLINE_DIR"

## Misc local variables
KERNEL_COMMANDLINE="$(xargs < "$ENV_KERNEL_COMMANDLINE_DIR/commandline.txt")"

##########################################################################################
## INITIAL CONFIG                                                                       ##
##########################################################################################

echo ':: Installing DE...'
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

##########################################################################################
## CONFIGURE FOR AI                                                                     ##
##########################################################################################

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
apt install -y tesseract-ocr

echo ':: Setting up Docker...'
apt install -y docker.io
systemctl enable docker
systemctl start docker
usermod -aG docker "$USERNAME"

echo ':: Setting up ROCm...'
apt install -y wget gnupg2 ca-certificates
wget -qO - https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor | tee /usr/share/keyrings/rocm.gpg > /dev/null
ROCM_VERSION=latest
ROCM_DISTRO=noble #TODO: Change once Resolute Racoon (26.04) comes out.
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/$ROCM_VERSION/Dists/$ROCM_DISTRO $ROCM_DISTRO main" > /etc/apt/sources.list.d/rocm.list
apt update
apt install -y rocm-core rocm-hip-runtime rocm-opencl-runtime rocminfo
usermod -aG video,render "$USERNAME"

echo ':: Testing ROCm...'
rocminfo || echo "ROCm failed to initialize; check kernel/firmware compatibility." >&2
su "$USERNAME" -c "docker run --rm -it \
--device=/dev/kfd \
--device=/dev/dri \
--group-add video \
--group-add render \
rocm/rocm-terminal \
rocminfo
"

echo ':: Setting up directories...'
AI_DIR=/srv/ai
mkdir -p "$AI_DIR"
chown -R "$USERNAME" "$AI_DIR"

##########################################################################################
## ADDITIONAL CONFIGURATION                                                             ##
##########################################################################################

## Sysctl
echo ':: Configuring sysctl...'
idempotent_append 'vm.max_map_count = 1048576'         '/etc/sysctl.d/99-ai.conf'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/62-io-tweakable.conf
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

##########################################################################################
## OUTRO                                                                                ##
##########################################################################################

## Wrap up
echo ':: Creating snapshot...'
set +e
zfs snapshot -r "$ENV_POOL_NAME_OS@install-morpheus"
set -e

## Done
echo ':: Done.'
exit 0
