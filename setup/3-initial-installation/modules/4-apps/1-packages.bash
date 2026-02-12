#!/usr/bin/env bash

## Install daemons
echo ':: Installing daemons...'
## Generally useful
apt install -y chrony clamav clamav-daemon systemd-oomd
systemctl enable chrony
systemctl enable clamav-daemon
systemctl enable clamav-freshclam
systemctl enable systemd-oomd
## Niche
apt install -y rasdaemon fail2ban
systemctl enable fail2ban
systemctl enable rasdaemon
## Follow-up
systemctl mask systemd-coredump.socket systemd-coredump@.service

## Install firmware
echo ':: Installing firmware, drivers, and tools...'
## General firmware
apt install -y firmware-linux-free firmware-linux-nonfree firmware-misc-nonfree
## General firmware tools
apt install -y fwupd iasl
## General hardware tools
KVER=$(ls /lib/modules | sort -V | tail -n1) #NOTE: Can't use `uname -r` since that'd be the LiveCD's kernel.
apt install -y linux-tools-common "linux-tools-$KVER" i2c-tools ethtool fancontrol lm-sensors lshw net-tools pciutils read-edid smartmontools hdparm tpm2-tools usbutils sysstat iotop dmsetup numactl numatop procps psmisc cgroup-tools mesa-utils clinfo nvme-cli
unset KVER
sensors-detect --auto

## Install applications
echo ':: Installing applications...'
## Applications that need configuration
[[ $DISTRO -eq 1 ]] && tasksel --new-install
apt install -y popularity-contest
## Common applications
apt install -y cups rsync
## Niche applications
# apt install -y # sanoid
