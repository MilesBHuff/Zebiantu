#!/usr/bin/env bash
function helptext {
    echo "Usage: configure-duat.bash"
    echo
    echo 'This is a one-shot script that finishes setting up Duat (using Ubuntu).'
    echo 'Duat is the host for Anubis, an OPNsense guest VM acting as a firewall and edge router.'
    echo 'It runs on a BeeLink with an Intel N100, a 128G RAID1 array of two single-lane NVMes, and 16G of non-ECC DDR5 SODIMM memory.'
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
    -z "$ENV_INSTALLER_ENVFILE" ||\
    -z "$ENV_POOL_NAME_OS"
]]; then
    echo "ERROR: Missing variables in '$ENV_FILE'!" >&2
    exit 3
fi
source "$ENV_INSTALLER_ENVFILE"
if [[
    -z "$KERNEL_COMMANDLINE_DIR" ||\
    -z "$UBUNTU_VERSION" ||\
    -z "$USERNAME"
]]; then
    echo "ERROR: Missing variables in '$ENV_INSTALLER_ENVFILE'!" >&2
    exit 4
fi

## Variables
KERNEL_COMMANDLINE="$(xargs < "$KERNEL_COMMANDLINE_DIR/commandline.txt")"

echo ':: Installing Ubuntu Server...'
# apt install -y ubuntu-server-minimal
apt install -y ubuntu-server

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
apt install -y intel-microcode firmware-intel-graphics firmware-realtek
## Controllers
apt install -y -t "$UBUNTU_VERSION-backports" openrgb

## Configure VM and VM-related networking
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE intel_iommu=on iommu=pt intremap=on pcie_acs_override=downstream,multifunction" #WARN: The second two flags here may not be necessary, but are included out of caution. Run `find /sys/kernel/iommu_groups/ -type l` without them to verify whether the NICs are properly isolated; if they are, then remove these flags.
VMNET_ID='????'
VNET_ID='vnet0'
NM_VNET_ID='vnet'
OPNSENSE_ISO='/root/Downloads/OPNsense.iso'
VDISK="$ENV_POOL_NAME_OS/data/srv/anubis"
declare -i MEMORY=8192 ## Leaves 8192 for the host. (We're swimming in RAM; neither will ever need as much as they have.)
declare -i STORAGE=96 ## In gigabytes. Make sure you leave enough for the host to be cozy.
declare -i CORES=$(nproc) ## While it may seem nice to reserve 1 CPU entirely for the host, I don't think that's worth removing 25% of the guest's cores.
declare -i VOLBLOCKSIZE=4 ## `4` avoids RMW in exchange for more metadata. We are neither storage-limited nor memory-limited in this appliance, so this is the right value.
## Create zvol for VM
zfs create -V "${STORAGE}G" -o volblocksize="${VOLBLOCKSIZE}K" -o volmode=dev "$VDISK"
## Create VM for OPNsense
virt-install \
    --name anubis \
    --memory $MEMORY \
    --vcpus $CORES \
    --network network="$VMNET_ID",model=virtio \
    --disk path="/dev/zvol/$VDISK",format=raw,bus=virtio,discard=unmap \
    --cdrom "$OPNSENSE_ISO" \
    --os-variant freebsd13.2 \
    --graphics none \
    --console pty,target_type=serial \
    --cpu host-passthrough ## Needed to ensure features like AES-NI function optimally.
## Create $VNET_ID as virtio-net interface
#TODO
## Start VM on boot, before NetworkManager comes up
#TODO
## Install prerequisites before we mess with networking
apt install -y nftables
systemctl enable nftables
## Configure $VNET_ID in NM
nmcli con add type ethernet ifname "$VNET_ID" con-name "$NM_VNET_ID" \
    ipv4.method auto \
    ipv6.method auto \
    ipv4.never-default no \
    ipv6.never-default no \
    connection.autoconnect yes
nmcli con up "$NM_VNET_ID"
## Tell NM not to manage physical NICs
cat > /etc/NetworkManager/conf.d/99-only-manage-virtio-net.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:en*,interface-name:wl*
EOF
systemctl restart NetworkManager
## Use a firewall rule to make extra-sure that host does not use its physical ports
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
    chain input {
        type filter hook input priority 0;
        policy accept;
    }
    chain forward {
        type filter hook forward priority 0;
        policy drop;
    }
    chain output {
        type filter hook output priority 0;
        policy drop;
        oifname "lo" accept
        oifname "$VNET_ID" accept
    }
}
EOF
systemctl start nftables
## Configure physical NICs for passthrough #WARN: FreeBSD Wi-Fi support is... *spotty*, to say the least.
cat > /etc/udev/rules.d/99-nic-passthrough.rules <<'EOF'
SUBSYSTEM=="pci", ATTR{class}=="0x020000", ATTR{driver_override}="vfio-pci"
SUBSYSTEM=="pci", ATTR{class}=="0x028000", ATTR{driver_override}="vfio-pci"
EOF
## Load vfio-pci EARLY in boot
echo vfio-pci > /etc/modules-load.d/vfio-pci.conf
idempotent_append 'vfio' '/etc/initramfs-tools/modules'
idempotent_append 'vfio_pci' '/etc/initramfs-tools/modules'
idempotent_append 'vfio_iommu_type1' '/etc/initramfs-tools/modules'
#TODO: Make sure that USB NICs will still work normally; I want the option of plugging one in.

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
sysctl --system

## Set kernel commandline
echo "$KERNEL_COMMANDLINE" > "$KERNEL_COMMANDLINE_DIR/commandline.txt"
"$KERNEL_COMMANDLINE_DIR/set-commandline"
update-initramfs -u

## Wrap up
echo ':: Creating snapshot...'
set +e
zfs snapshot -r "$ENV_POOL_NAME_OS@install-duat"
set -e

## Done
echo ':: Done.'
exit 0
