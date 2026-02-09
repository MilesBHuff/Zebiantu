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
    echo
    echo 'You must run this in-person via keyboard+display because it *will* break networking.'
    echo 'If the VM ever goes down, you will have to be physically present to fix things; there is no simple+safe way to expose ssh to this host over WAN.'
    echo '(Note that this physical access requirement is no different than what would exist were we running OPNsense on bare metal.)'
    echo
    echo 'Why bother? Well, Linux can do all of the following where FreeBSD either struggles or simply can’t: TPM, SecureBoot, ZFSBootManager, optimal hardware support, latest microcode, firmware updates.'
    echo 'Running OPNsense in a VM on a Linux host gives us the best of all worlds. Yes, it adds some complexity, but it removes other complexities and provides a level of security that just isn’t possible with a bare-metal BSD system.'
    echo
    echo 'A router is an absurdly high-value target for an evil-maid attack: it has the ability to see everything your network is doing, it can MITM literally everything, it can effortlessly exfiltrate anything it sees, and more.'
    echo 'A router is also one of the easiest devices to compromise: It’s left alone in the open without supervision 99% of the time, and it is rarely even superficially inspected.'
    echo 'So I must insist that what is insane is not that I’ve gone through the effort of writing this script; it’s that others view this level of security — the bare minimum needed to prevent trivial evil-maid attacks — as unreasonable.'
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
    -z "$UBUNTU_VERSION"
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
# systemctl mask systemd-networkd #TODO: Do we want this masked?
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
## TPM                                                                                  ##
##########################################################################################
## Set up auto-unlock via TPM — an edge router that requires manual intervention on every boot is not a good edge router.
## The main thing that needs to be done for this is a custom ZBM that contains the sealed key and instructions for how to unseal it. We don't actually have to go through the trouble of storing the sealed key in the initramfs because the system can auto-load the raw key from /etc/zfs/keys after ZBM unlocks it.
## If the ESP flashdrive ever dies or gets corrupted, the recovery path is pretty simple: new flashdrive, vanilla ZBM, temp disable SB, manual unlock, regenerate custom ZBM, reboot, reenable SB.

## Make sure we actually have a TPM.
if [[ ! -e /dev/tpmrm0 ]]; then
    echo "ERROR: No TPM detected!"
    exit 5
fi

## Install requisites
apt install -y clevis clevis-tpm2 tpm2-tools

## Clear the TPM
#NOTE: Apparently there aren't great ways to do this from the OS; it should be done at firmware level.

## Seal to TPM
KEY="/etc/zfs/keys/$ENV_POOL_NAME_OS.key"
BLOB_DIR='/etc/zfsbootmenu/keys'
BLOB="$BLOB_DIR/$ENV_POOL_NAME_OS.jwe"
install -dm 0755 "$BLOB_DIR"
clevis encrypt tpm2 '{"pcr_ids":"7"}' < "$KEY" > "$BLOB"
unset KEY
chmod 0600 "$BLOB"
sync
clevis decrypt < "$BLOB" | head -n 1

## Ensure ZBM is capable of unsealing the key.
install -dm 0755 /etc/zfsbootmenu/dracut.conf.d
cat > /etc/zfsbootmenu/dracut.conf.d/50-tpm-unseal.conf <<EOF && chmod 644 /etc/zfsbootmenu/dracut.conf.d/50-tpm-unseal.conf #AI
install_items+=" $BLOB /usr/bin/clevis /usr/bin/jose /usr/lib/clevis/ /usr/libexec/clevis/ "
EOF

## Make ZBM unseal the key.
install -dm 0755 /etc/zfsbootmenu/hooks/load-key.d
cat > /etc/zfsbootmenu/hooks/load-key.d/10-tpm-unseal <<EOF && chmod 755 /etc/zfsbootmenu/hooks/load-key.d/10-tpm-unseal #AI
#!/bin/sh
set -eu
## ZBM provides these (see zfsbootmenu(7)): ZBM_LOCKED_FS, ZBM_ENCRYPTION_ROOT
BLOB="$BLOB"
TMP='/run/zfskey.pass'
command -v clevis >/dev/null 2>&1 || exit 0
[ -s "\$BLOB" ] || exit 0
umask 077
rm -f "\$TMP"
if ! clevis decrypt < "\$BLOB" > "\$TMP" 2>/dev/null; then
    rm -f "\$TMP"
    exit 0
fi
[ -f "\$ZBM_ENCRYPTION_ROOT" ] || exit 1
zfs load-key -L "file://\$TMP" "\$ZBM_ENCRYPTION_ROOT" >/dev/null 2>&1 || true
rm -f "\$TMP"
exit 0
EOF

## Update ZBM
generate-zbm

##########################################################################################
## CONFIGURE VM + NETWORKING                                                            ##
##########################################################################################
echo ':: Configuring virtualization and networking...'
## The networking goal is to passthrough to the guest all physical Ethernet interfaces that are present during this installer.
## Wi-Fi is not passed-through; FreeBSD has poor support for it. Also, I simply don't intend for this box to ever handle Wi-Fi.
## That said, if I ever do decide to do Wi-Fi here, it would likely be via a second VM running OpenWRT — not via the OPNsense VM.
## Because only present-at-install-time Ethernet interfaces are passed-through, a USB interface can later be added as a way for the host to get a real management interface.
read -rp 'Please ensure any Ethernet interfaces you want the host to own are not plugged-into the system. Press "Enter" to continue when ready. ' _; unset _

## Requisite kernel commandline flags
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE intel_iommu=on iommu=pt" ## PT is fine, since guest compromise makes the host useless anyway. The CPU is weak-enough that we need the extra performance.
echo 'IOMMU Groups: '
find /sys/kernel/iommu_groups/ -type l
read -rp 'Enter "n" if the Ethernet interfaces are not sufficiently isolated, or "y" if they are. ' ISOLATED
if [[ "$ISOLATED" == 'n' ]]; then
    KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE pcie_acs_override=downstream,multifunction"
    echo 'WARN: Lying about real IOMMU groupings to the kernel to permit network interface passthrough. This will reduce security!' >&2 ## Should be fine given that this is a single-VM appliance — pwning the host isn't much worse than pwning the guest.
fi

## Install prerequisites before we mess with networking
apt install -y nftables qemu-kvm libvirt-daemon-system libvirt-clients virtinst ovmf bridge-utils

## Load vfio stuff early in boot
idempotent_append 'vfio' '/etc/initramfs-tools/modules'
idempotent_append 'vfio_pci' '/etc/initramfs-tools/modules'
idempotent_append 'vfio_iommu_type1' '/etc/initramfs-tools/modules'
update-initramfs -u

## Find all local Ethernet interfaces
mapfile -t PCI_ADDRS < <( lspci -Dn | awk '$2 ~ /^0200$/ { print $1 }' ) #AI
mapfile -t IF_MACS < <( nmcli -t -f DEVICE,TYPE,GENERAL.HWADDR device | awk -F: '$2=="ethernet" && $3!="" { print tolower($3) }' ) #AI
BR_ID='br-anubis'

## Configure Ethernet for passthrough
{ for PCI_ADDR in "${PCI_ADDRS[@]}"; do
    echo "SUBSYSTEM==\"pci\", KERNELS==\"0000:${PCI_ADDR}\", ATTR{driver_override}=\"vfio-pci\""
done } > /etc/udev/rules.d/99-nic-passthrough.rules
udevadm control --reload-rules
udevadm trigger --subsystem-match=pci

## Tell NM not to manage what we are virtualizing
UNMANAGED_DEVICES=''
for IF_NAME in "${IF_MACS[@]}"; do
    [[ -n "$UNMANAGED_DEVICES" ]] && UNMANAGED_DEVICES+=';'
    UNMANAGED_DEVICES+="mac:$IF_NAME"
done
cat > /etc/NetworkManager/conf.d/99-unmanage-ethernet.conf <<EOF
[keyfile]
unmanaged-devices=$UNMANAGED_DEVICES
EOF
systemctl restart NetworkManager

## Use a firewall rule to ensure the host does not use the passed-through interfaces.
#TODO: Maybe make it so that this supports later-inserted USB Ethernet interfaces.
cat > /etc/nftables.conf <<EOF #AI
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
    chain input {
        type filter hook input priority 0;
        policy drop;
        iifname "lo" accept
        ct state established,related accept
        iifname "$BR_ID" udp sport 67 udp dport 68 accept
        oifname "$BR_ID" udp sport 68 udp dport 67 accept
        iifname "$BR_ID" tcp dport 22 accept
        iifname "$BR_ID" ip protocol icmp accept
        iifname "$BR_ID" ip6 nexthdr icmpv6 accept
    }
    chain output {
        type filter hook output priority 0;
        policy reject;
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

## Create virtual network interface so that the host can conect via the guest.
nmcli con add type bridge ifname "$BR_ID" con-name "$BR_ID" \
    ipv4.method auto \
    ipv6.method auto \
    ipv4.never-default no \
    ipv6.never-default no \
    ipv4.may-fail no \
    ipv6.may-fail no \
    connection.autoconnect yes \
    autoconnect-priority 10 \
    connection.autoconnect-retries -1
nmcli con up "$BR_ID"

## Create a zvol for the VM.
ANUBIS_DIR='/srv/anubis'
VDISK="$ENV_POOL_NAME_OS/data$ANUBIS_DIR/zvol"
if ! zfs list -Ho name "$VDISK" >/dev/null 2>&1; then
    declare -i STORAGE=96 ## In gigabytes. Make sure you leave enough for the host to be cozy.
    declare -i VOLBLOCKSIZE=4 ## `4` matches ashift=12 and so avoids RMW in exchange for more metadata. We are neither storage-limited nor memory-limited in this appliance, so this is the right value.
    zfs create -V "${STORAGE}G" -o volblocksize="${VOLBLOCKSIZE}K" -o volmode=dev "$VDISK"
fi

## Create VM for OPNsense
declare -a HOSTDEV_ARGS=()
for PCI_ADDR in "${PCI_ADDRS[@]}"; do
    HOSTDEV_ARGS+=('--hostdev' "$PCI_ADDR")
done
declare -i MEMORY=8192 ## Leaves 8192 for the host. (We're swimming in RAM; neither will ever need as much as they have.)
declare -i SHARES=512 ## Host should be 1024. 1024/512==2, so host threads should have twice the priority of guest tasks under contention.
declare -i CORES=$(nproc) ## The guest needs access to all 4; firewalling can be demanding. SHARES is how we're avoiding guest spikes from locking up the host.
FREEBSD_VERSION='freebsd14'
OPNSENSE_ISO="$ANUBIS_DIR/OPNsense.iso"
if [[ ! -f "$OPNSENSE_ISO" ]]; then
    echo "Please place an OPNsense installation ISO at '$OPNSENSE_ISO'." >&2
    exit 5
fi
virt-install \
    --name anubis \
    --memballoon none \
    --memory $MEMORY \
    --vcpus $CORES \
    --cputune shares=$SHARES \
    --network bridge="$BR_ID",model=virtio \
    --disk path="/dev/zvol/$VDISK",format=raw,bus=virtio,cache=none,discard=unmap \
    --cdrom "$OPNSENSE_ISO" \
    --osinfo "$FREEBSD_VERSION" \
    --graphics none \
    --console pty,target_type=serial \
    --boot uefi \
    "${HOSTDEV_ARGS[@]}" \
    --cpu host-passthrough ## Needed to ensure features like AES-NI function optimally.
echo 'It is now safe to connect any Ethernet interfaces you want the host to own.'
echo 'In the OPNsense installer’s partitioner, please configure a GUID partition table, an EFI system partition, and a UFS root partition. (Do not use ZFS.)'
read -rp 'Press "Enter" to install OPNsense inside the VM. To exit, shut the VM down. ' _; unset _
virsh console anubis

## Start VM automatically
virsh autostart anubis
systemctl enable --now libvirtd
systemctl enable --now libvirt-guests

## Ensure VM comes up before NetworkManager — NM's depending on the VM means there's no point in allowing NM to load sooner.
## Note that NM will still repeatedly fail to connect during the time it takes for the guest to boot; this dependency here just reduces how many failures appear in the log.
mkdir -p /etc/systemd/system/NetworkManager.service.d
cat > /etc/systemd/system/NetworkManager.service.d/10-libvirt-first.conf <<'EOF'
[Unit]
After=libvirtd.service libvirt-guests.service
Wants=libvirtd.service
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
