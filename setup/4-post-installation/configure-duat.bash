#!/usr/bin/env bash
set -euo pipefail

################################################################################
## META                                                                       ##
################################################################################

function helptext {
    echo "Usage: configure-duat.bash"
    echo
    echo 'This is a one-shot script that finishes setting up Duat (using Ubuntu).'
    echo 'Duat is the host for Anubis, an OPNsense guest VM acting as a firewall and edge router.'
    echo 'It runs on a BeeLink with an Intel N100, a 128G RAID1 array of two single-lane NVMes, and 16G of non-ECC DDR5 SODIMM memory.'
}
## Special thanks to ChatGPT for helping with my endless questions.

################################################################################
## FUNCTIONS                                                                  ##
################################################################################

function idempotent_append { #TODO: Break into helper script, since it's re-used by other scripts.
    ## $1: What to append
    ## $2: Where to append it
    [[ ! -f "$2" ]] && touch "$2"
    grep -Fqx -- "$1" "$2" || printf '%s\n' "$1" >> "$2"
}

################################################################################
## ENVIRONMENT                                                                ##
################################################################################

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

##########################################################################################
## INITIAL CONFIG                                                                       ##
##########################################################################################

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

##########################################################################################
## CONFIGURE VM + NETWORKING                                                            ##
##########################################################################################

## Requisite kernel commandline flags
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE intel_iommu=on iommu=pt intremap=on pcie_acs_override=downstream,multifunction" #WARN: The second two flags here may not be necessary, but are included out of caution. Run `find /sys/kernel/iommu_groups/ -type l` without them to verify whether the NICs are properly isolated; if they are, then remove these flags.

## Install prerequisites before we mess with networking
apt install -y nftables qemu-kvm libvirt-daemon-system libvirt-clients virtinst ovmf bridge-utils

## Load vfio stuff early in boot
idempotent_append 'vfio' '/etc/initramfs-tools/modules'
idempotent_append 'vfio_pci' '/etc/initramfs-tools/modules'
idempotent_append 'vfio_iommu_type1' '/etc/initramfs-tools/modules'
echo vfio-pci > /etc/modules-load.d/vfio-pci.conf

## Find all local network interfaces
mapfile -t PCI_ADDRS < <(lspci -Dn | awk '$2 ~ /^02/ { print $1 }') #AI
BR_ID='br-anubis'

## Configure physical NICs for passthrough
cat > /etc/udev/rules.d/99-nic-passthrough.rules <<'EOF' #TODO: Have this only passthrough $PCI_ADDRS
SUBSYSTEM=="pci", ATTR{class}=="0x020000", ATTR{driver_override}="vfio-pci"
SUBSYSTEM=="pci", ATTR{class}=="0x028000", ATTR{driver_override}="vfio-pci"
EOF

## Tell NM not to manage what we are virtualizing
cat > /etc/NetworkManager/conf.d/99-unmanage-physical-interfaces.conf <<'EOF' #TODO: Have this only unmanage $PCI_ADDRS
[keyfile]
unmanaged-devices=interface-name:en*,interface-name:wl*
EOF
systemctl restart NetworkManager

## Use a firewall rule to ensure the host does not use the passed-through interfaces.
cat > /etc/nftables.conf <<EOF #AI
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
    chain input {
        type filter hook input priority 0;
        policy drop;
        ct state established,related accept
        iifname "lo" accept
        iifname "$BR_ID" tcp dport 22 accept
        iifname "$BR_ID" ip protocol icmp accept
        iifname "$BR_ID" ip6 nexthdr icmpv6 accept
    }
    chain output {
        type filter hook output priority 0;
        policy drop;
        ct state established,related accept
        oifname "lo" accept
        oifname "$BR_ID" accept
    }
    chain forward {
        type filter hook forward priority 0;
        policy drop;
    }
}
EOF
systemctl enable --now nftables

## Create virtual network interface so that host can conect via guest.
nmcli con add type bridge ifname "$BR_ID" con-name "$BR_ID" \
    ipv4.method auto \
    ipv6.method auto \
    ipv4.never-default no \
    ipv6.never-default no \
    connection.autoconnect yes
nmcli con up "$BR_ID"

## Create zvol for VM
VDISK="$ENV_POOL_NAME_OS/data/srv/anubis"
if ! zfs list -Ho name "$VDISK" >/dev/null 2>&1; then
    declare -i STORAGE=96 ## In gigabytes. Make sure you leave enough for the host to be cozy.
    declare -i VOLBLOCKSIZE=4 ## `4` avoids RMW in exchange for more metadata. We are neither storage-limited nor memory-limited in this appliance, so this is the right value.
    zfs create -V "${STORAGE}G" -o volblocksize="${VOLBLOCKSIZE}K" -o volmode=dev "$VDISK"
fi

## Create VM for OPNsense
declare -a HOSTDEV_ARGS=()
for PCI_ADDR in "${PCI_ADDRS[@]}"; do
    HOSTDEV_ARGS+=('--hostdev' "$PCI_ADDR")
done
declare -i MEMORY=8192 ## Leaves 8192 for the host. (We're swimming in RAM; neither will ever need as much as they have.)
declare -i CORES=$(nproc) ## While it may seem nice to reserve 1 CPU entirely for the host, I don't think that's worth removing 25% of the guest's cores.
FREEBSD_VERSION='freebsd14'
OPNSENSE_ISO='/root/Downloads/OPNsense.iso'
virt-install \
    --name anubis \
    --memory $MEMORY \
    --vcpus $CORES \
    --network bridge="$BR_ID",model=virtio \
    --disk path="/dev/zvol/$VDISK",format=raw,bus=virtio,discard=unmap \
    --cdrom "$OPNSENSE_ISO" \
    --osinfo "$FREEBSD_VERSION" \
    --graphics none \
    --console pty,target_type=serial \
    --boot uefi \
    "${HOSTDEV_ARGS[@]}" \
    --cpu host-passthrough ## Needed to ensure features like AES-NI function optimally.

## Start VM automatically
virsh autostart anubis
systemctl enable --now libvirtd
systemctl enable --now libvirt-guests

## Ensure VM comes up before NetworkManager, since NM depends on it
mkdir -p /etc/systemd/system/NetworkManager.service.d
cat > /etc/systemd/system/NetworkManager.service.d/10-libvirt-first.conf <<'EOF'
[Unit]
After=libvirtd.service libvirt-guests.service
Requires=libvirtd.service
EOF

##########################################################################################
## ADDITIONAL CONFIGURATION                                                             ##
##########################################################################################

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
"$KERNEL_COMMANDLINE_DIR/set-commandline" ## Sorts, deduplicates, and saves the new commandline.
update-initramfs -u

##########################################################################################
## OUTRO                                                                                ##
##########################################################################################

## Wrap up
echo ':: Creating snapshot...'
set +e
zfs snapshot -r "$ENV_POOL_NAME_OS@install-duat"
set -e

## Done
echo ':: Done.'
exit 0
