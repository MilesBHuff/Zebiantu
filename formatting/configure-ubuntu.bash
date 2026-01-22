#!/usr/bin/env bash
function helptext {
    echo "Usage: configure-ubuntu.bash"
    echo
    echo 'This oneshot script configures Ubuntu Server for a Framework Desktop.'
}
set -euo pipefail

echo ':: Editing repos...'
${EDITOR:-nano} /etc/apt/sources.list

echo ':: Updating and upgrading...'
apt update
apt full-upgrade
set +e
fwupdmgr refresh
fwupdmgr get-updates && fwupdmgr update
set -e

echo ':: Enabling automatic upgrades...'
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

echo ':: Installing DE...'
apt install -y ubuntu-desktop-minimal

echo ':: Disable DE by default...'
systemctl set-default multi-user.target
systemctl disable gdm

echo ':: Switching to NetworkManager from networkd...'
apt install -y networkmanager ## Just to be safe; should have already installed with the above.
systemctl enable NetworkManager
# systemctl start NetworkManager
mkdir -p /etc/netplan ## Just to be safe.
cat > /etc/netplan/99-use-networkmanager.yaml <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
netplan apply
systemctl disable systemd-networkd
# systemctl stop systemd-networkd
systemctl mask systemd-networkd
apt purge systemd-networkd

echo ':: Disabling Wi-Fi...'
nmcli radio wifi off
nmcli general reload

################################################################################
#NOTE: Keep the below snippets synchronized with `install-debian-from-chroot.bash`.

declare -a KERNEL_PARAMS=()

echo ':: Configuring Wake-On-LAN...'
cat > /etc/udev/rules.d/99-wol.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="net", KERNEL=="en*", RUN+="/usr/sbin/ethtool -s %k wol g"
ACTION=="add", SUBSYSTEM=="net", KERNEL=="eth*", RUN+="/usr/sbin/ethtool -s %k wol g"
EOF

echo ':: Configuring swap...'
KERNEL_PARAMS+=('zswap.enabled=1' 'zswap.max_pool_percent=17' 'zswap.compressor=lzo') #NOTE: Fractional percents (eg, `12.5`) are not possible.
apt install -y systemd-zram-generator
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = "ram * 0.3333333"
compression-algorithm = "zstd"
swap-priority = 32767
EOF
systemctl daemon-reload
systemctl start systemd-zram-setup@zram0

echo ':: Scheduling trim...'
systemctl enable fstrim.timer ## Auto-trims everything in /etc/fstab
#TODO: Auto-trim zpools, too.

echo ':: Installing daemons...'
## Generally useful
apt install -y chrony clamav clamav-daemon systemd-oomd
systemctl enable chrony ## Should be present by default on Ubuntu Server, but we'll do this just in case.
systemctl enable clamav-daemon
systemctl enable clamav-freshclam
systemctl enable systemd-oomd ## Should be enabled by default on Ubuntu, but we'll do this just in case.
## Niche
apt install -y rasdaemon fail2ban nut-client
systemctl enable fail2ban
systemctl enable rasdaemon
systemctl enable nut-client #TODO: Configure to point at NAS.
systemctl enable nut-monitor
## Follow-up
systemctl mask systemd-coredump.socket systemd-coredump@.service

echo ':: Installing firmware, drivers, and tools...'
## General hardware tools
apt install -y linux-tools-common linux-tools-$(uname -r) i2c-tools ethtool fancontrol lm-sensors lshw net-tools pciutils read-edid smartmontools hdparm tpm2-tools usbutils sysstat iotop dmsetup numactl numatop procps psmisc cgroup-tools mesa-utils clinfo
sensors-detect --auto
## Specific firmware
apt install -y amd64-microcode firmware-amd-graphics firmware-mellanox firmware-realtek

echo ':: Installing applications...'
## Applications that need configuration
apt install -y popularity-contest
## Common applications
apt install -y rsync unzip
## Niche applications
# apt install -y

echo ':: Additional configurations...'
KERNEL_PARAMS+=('page_alloc.shuffle=1')
read -p 'Please enter your wireless regulatory domain: ('US' for the USA) ' REGDOM
KERNEL_PARAMS+=("cfg80211.ieee80211_regdom=$REGDOM")
unset REGDOM

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

echo ':: Modifying filesystem hierarchy...'
bash ./configure-filesystem-hierarchy.bash

echo ':: Setting kernel commandline...'
for PARAM in "${KERNEL_PARAMS[@]}"; do
  if ! grep -qw "$PARAM" /etc/default/grub; then
    sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=".*\)"/\1 '"$PARAM"'"/' /etc/default/grub
  fi
done
update-grub

echo ':: Creating snapshot...'
zfs snapshot -r rpool@install-ubuntu

## Done
echo ':: Done.'
exit 0
