#!/usr/bin/env bash
function helptext {
    echo "Usage: configure-artemis.bash"
    echo
    echo 'This is a one-shot script that finishes setting up Artemis (using Debian) in a chroot.'
    echo 'Artemis is a NAS and home server running on a custom-built computer.'
}
## Special thanks to ChatGPT for helping with my endless questions.
set -euo pipefail

## Variables
KERNEL_COMMANDLINE="$(cat "$KERNEL_COMMANDLINE_DIR/commandline.txt" | xargs)"

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
## Tools
apt install -y ipmitool mstflint openseachest
#TODO: Install proprietary tools: STORCLI MFT
# systemctl enable mst
## Controllers
apt install -y -t "$DEBIAN_VERSION-backports" openrgb

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
# systemctl start infnoise ## Shouldn't start/stop from chroot.

## Configure CPU features
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE amd_iommu=on" ## Leaving `iommu=pt` off for security.
cat > /etc/modprobe.d/kvm-amd.conf <<'EOF'
options kvm-amd nested=1
EOF

## Sysctl
echo ':: Configuring sysctl...'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/61-io.conf
cat > /etc/sysctl.d/62-io-tweakable.conf <<'EOF'
vm.zone_reclaim_mode=0
vm.swappiness=134
vm.vfs_cache_pressure=50
vm.vfs_cache_pressure_denom=100
kernel.mm.ksm.run=1
kernel.mm.ksm.pages_to_scan=100
kernel.mm.ksm.sleep_millisecs=1000
vm.dirty_writeback_centisecs=500
vm.dirty_expire_centisecs=1500
vm.dirty_bytes=1250000000
vm.dirty_background_bytes=625000000
EOF

## Set kernel commandline
echo "$KERNEL_COMMANDLINE" > "$KERNEL_COMMANDLINE_DIR/commandline.txt"
"$KERNEL_COMMANDLINE_DIR/set-commandline"

## Wrap up
echo ':: Creating snapshot...'
set +e
zfs snapshot -r "$ENV_POOL_NAME_OS@install-artemis"
set -e

## Done
exec ./convert-debian-to-proxmox.bash
