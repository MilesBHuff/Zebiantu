#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob
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
    echo 'Why bother? Well, Linux can do all of the following where FreeBSD either struggles or simply can’t: TPM, SecureBoot, ZFSBootManager, optimal hardware support, latest microcode, firmware updates, RAID1 ESP.'
    echo 'Running OPNsense in a VM on a Linux host gives us the best of all worlds. Yes, it adds some complexity, but it removes other complexities and provides a level of security that just isn’t possible with a bare-metal BSD system.'
    echo
    echo 'A router is an absurdly high-value target for an evil-maid attack: it has the ability to see everything your network is doing, it can MITM literally everything, it can effortlessly exfiltrate anything it sees, and more.'
    echo 'A router is also one of the easiest devices to compromise: It’s left alone in the open without supervision 99% of the time, and it is rarely even superficially inspected.'
    echo 'So I must insist that what is insane is not that I’ve gone through the effort of writing this script; it’s that others view this level of security — the bare minimum needed to prevent trivial evil-maid attacks — as unreasonable.'
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
    ENV_KERNEL_COMMANDLINE_DIR

echo ':: Declaring variables...'
## Misc local variables
KERNEL_COMMANDLINE="$(xargs < "$ENV_KERNEL_COMMANDLINE_DIR/commandline.txt")"
TEMP_ENV_FILE='/configure-duat.env.bash'

ANSWER='0'
while true; do
    read -rp "Submit \`1\` to run pre-VM setup, or \`2\` to run VM setup: " ANSWER
    [[ "$ANSWER" == '1' || "$ANSWER" == '2' ]] && break
done
declare -i SECTION=$ANSWER
unset ANSWER
if [[ $SECTION -eq 1 ]]; then

    #####################################
    ##   I N I T I A L   C O N F I G   ##
    #####################################

    echo ':: Installing base system...'
    apt install -y ubuntu-server

    echo ':: Installing system-specific things...'
    ## Daemons
    apt install -y nut-client
    systemctl enable nut-client
    ## Drivers
    apt install -y intel-microcode firmware-intel-graphics firmware-realtek

    #################################
    ##   P O W E R   O N / O F F   ##
    #################################

    #TODO: VM could be suspended before hibernation, to reduce RAM requirements; then automatically resumed after restore.

    #TODO: VM must be suspended or shut-down before any restart or power-off.

    systemctl enable reboot.timer ## We need to restart daily because this box does not have ECC.

    #############################
    ##   S C H E D U L I N G   ##
    #############################
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

    reschedule-timer "zfs-scrub@$ENV_POOL_NAME_OS.timer" '*-*-1 1:00'          '10m' '0'
    # reschedule-timer 'smart-short@.timer'               '*-*-7,14,21,28 0:00' '10m' '0' #TODO: Get drive WWN (`/dev/disk/by-id/`).
    # reschedule-timer 'smart-short@.timer'               '*-*-7,14,21,28 0:00' '10m' '0' #TODO: Get drive WWN (`/dev/disk/by-id/`).
    reschedule-timer 'fstrim.timer'                       '*-*-7,14,21,28 2:00' '10m' '0'
    reschedule-timer 'zfstrim.timer'                      '*-*-7,14,21,28 2:00' '10m' '0'
    reschedule-timer 'reboot.timer'                       '*-*-* 6:00'          '10m' '0'

    systemctl daemon-reload

    #########################################################
    ##   A D D I T I O N A L   C O N F I G U R A T I O N   ##
    #########################################################

    echo ':: Configuring memory...'
    ## Set a more-restrictive max size for tmpfs
    sed -i 's/size=5G/size=1G/' '/etc/systemd/system/tmp.mount.d/override.conf'
    ## Disable high-compression zram writeback devices
    sed -i 's/writeback-device = \/dev\/zram1//' '/etc/systemd/zram-generator.conf.d/zram0.conf'
    rm -f '/etc/systemd/zram-generator.conf.d/zram1.conf'
    rm -rf '/etc/systemd/system/systemd-zram-setup@zram0.service.d'
    rm -rf '/etc/systemd/system/systemd-zram-setup@zram1.service.d'

    ## Sysctl
    echo ':: Configuring sysctl...'
    ### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/62-io-tweakable.conf
    sed -iE           's/^(vm\.swappiness)=[0-9]+$/\1=96/' '/etc/sysctl.d/62-io-tweakable.conf' ## AI-estimated per Duat's specific hardware and the formula given in `mem-fs.bash`.
    idempotent_append 'kernel.mm.ksm.run=0'                '/etc/sysctl.d/62-io-tweakable.conf'
    idempotent_append 'kernel.mm.ksm.pages_to_scan=100'    '/etc/sysctl.d/62-io-tweakable.conf'
    idempotent_append 'kernel.mm.ksm.sleep_millisecs=1000' '/etc/sysctl.d/62-io-tweakable.conf'
    idempotent_append 'vm.dirty_writeback_centisecs=500'   '/etc/sysctl.d/62-io-tweakable.conf'
    idempotent_append 'vm.dirty_expire_centisecs=1500'     '/etc/sysctl.d/62-io-tweakable.conf'
    sysctl --system

    ###################################################################
    ##   V M   &   N E T W O R K I N G   ( P R E - R E S T A R T )   ##
    ###################################################################
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

    #########################
    ##   O U T R O   # 1   ##
    #########################

    ## Set kernel commandline
    echo ':: Setting kernel commandline...'
    echo "$KERNEL_COMMANDLINE" > "$ENV_KERNEL_COMMANDLINE_DIR/commandline.txt"
    "$ENV_KERNEL_COMMANDLINE_DIR/set-commandline" ## Sorts, deduplicates, and saves the new commandline.
    update-initramfs -u

    ## Save variables
    cat > "$TEMP_ENV_FILE" <<EOF && chmod 700 "$TEMP_ENV_FILE"
#!/usr/bin/env bash
$(declare -p PCI_ADDRS)
$(declare -p BR_ID)
$(declare -p ANUBIS_DIR)
$(declare -p VDISK)
EOF

    ## Snapshot
    echo ':: Creating snapshot...'
    set +e
    zfs snapshot -r "$ENV_POOL_NAME_OS@install-duat"
    set -e

    ## Notify user
    read -r 'Please re-run this script and submit \`2\` when asked which section to run. (Press \`Enter\` to acknowledge and continue.) ' _; unset _

    ## Done
    echo ':: Restarting...'
    exec systemctl reboot

else
    #####################################################################
    ##   V M   &   N E T W O R K I N G   ( P O S T - R E S T A R T )   ##
    #####################################################################

    ## Restore variables
    if [[ ! -f "$TEMP_ENV_FILE" ]]; then
        echo "ERROR: Missing \`$TEMP_ENV_FILE\`."
        exit 2
    fi
    source "$TEMP_ENV_FILE"
    unset TEMP_ENV_FILE

    ## Make sure we're safe to continue
    echo ':: Verifying IOMMU is enabled...'
    if [[ ! -d /sys/kernel/iommu_groups ]]; then
        echo 'ERROR: IOMMU not enabled.'
        exit 3
    fi
    echo ':: Verifying NICs bound to `vfio-pci`...'
    for PCI_ADDR in "${PCI_ADDRS[@]}"; do
        if ! lspci -nnks "$PCI_ADDR" | grep -q 'Kernel driver in use: vfio-pci'; then
            echo "ERROR: $PCI_ADDR not bound to vfio-pci."
            exit 4
        fi
    done

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
        --channel unix,target_type=virtio,name=org.qemu.guest_agent.0 \
        --disk path="/dev/zvol/$VDISK",format=raw,bus=virtio,cache=none,discard=unmap \
        --cdrom "$OPNSENSE_ISO" \
        --osinfo "$FREEBSD_VERSION" \
        --graphics none \
        --console pty,target_type=serial \
        --serial pty \
        --boot uefi \
        "${HOSTDEV_ARGS[@]}" \
        --cpu host-passthrough ## Needed to ensure features like AES-NI function optimally.
    echo 'It is now safe to connect any Ethernet interfaces you want the host to own.'
    echo 'In the OPNsense installer’s partitioner, please configure a GUID partition table, an EFI system partition, and a UFS root partition. (Do not use ZFS.)'
    echo 'Once OPNsense is live, install the `os-qemu-guest-agent` package and enable its features.'
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

    ## Anubis's serial console gets TTY11.
    sudo systemctl enable --now vm-to-tty@anubis:11.service

    #########################
    ##   O U T R O   # 2   ##
    #########################
    rm -f "$TEMP_ENV_FILE"

    ## Snapshot
    echo ':: Creating snapshot...'
    set +e
    zfs snapshot -r "$ENV_POOL_NAME_OS@install-anubis"
    set -e

    ## Done
    echo ':: Done.'
    exit 0
fi
