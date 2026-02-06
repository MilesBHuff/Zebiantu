#!/usr/bin/env bash
function helptext {
    echo "Usage: configure-hephaestus.bash"
    echo
    echo 'This one-shot script configures Ubuntu Server for AI inference on a Framework Desktop.'
}
## Special thanks to ChatGPT for helping with my endless questions.
set -euo pipefail

## Get environment
ENV_FILE='../../env.sh'
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "ERROR: Missing '$ENV_FILE'." >&2
    exit 2
fi
if [[
    -z "$ENV_POOL_NAME_OS"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi
if [[
    -z "$KERNEL_COMMANDLINE_DIR" ||\
    -z "$UBUNTU_VERSION" ||\
    -z "$USERNAME"
]]; then
    echo "ERROR: This script is designed to be executed by \`install-deb-distro-from-chroot.bash\`." >&2
    exit 4
fi

## Variables
KERNEL_COMMANDLINE="$(cat "$KERNEL_COMMANDLINE_DIR/commandline.txt" | xargs)"

echo ':: Installing Ubuntu Server...'
# apt install -y ubuntu-server-minimal
apt install -y ubuntu-server

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
# systemctl stop systemd-networkd ## Shouldn't start/stop from chroot.
# systemctl start NetworkManager ## Shouldn't start/stop from chroot.
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

echo ':: Adjusting limits...'
cat > /etc/sysctl.d/99-ai.conf <<EOF
vm.max_map_count = 1048576
EOF
sysctl --system

echo ':: Setting up Docker...'
apt install -y docker.io
systemctl enable docker
# systemctl start docker ## Shouldn't start/stop from chroot.
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
chown "$USERNAME" "$AI_DIR"

## Sysctl
echo ':: Configuring sysctl...'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/61-io.conf
cat > /etc/sysctl.d/62-io-tweakable.conf <<'EOF'
vm.zone_reclaim_mode=0
vm.swappiness=134
vm.vfs_cache_pressure=50
vm.vfs_cache_pressure_denom=100
kernel.mm.ksm.run=0
kernel.mm.ksm.pages_to_scan=100
kernel.mm.ksm.sleep_millisecs=1000
vm.dirty_writeback_centisecs=500
vm.dirty_expire_centisecs=1500
EOF

## Set kernel commandline
echo "$KERNEL_COMMANDLINE" > "$KERNEL_COMMANDLINE_DIR/commandline.txt"
"$KERNEL_COMMANDLINE_DIR/set-commandline"

## Wrap up
echo ':: Creating snapshot...'
set +e
zfs snapshot -r "$ENV_POOL_NAME_OS@install-hephaestus"
set -e

## Done
echo ':: Done.'
exit 0
