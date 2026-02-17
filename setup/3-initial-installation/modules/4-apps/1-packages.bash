#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

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
echo ':: Installing firmware, drivers, and related tools...'
## Firmware
apt install -y \
    firmware-linux-free \
    firmware-linux-nonfree \
    firmware-misc-nonfree
## Firmware tools
KVER=$(ls /lib/modules | sort -V | tail -n1) #NOTE: Can't use `uname -r` since that'd be the LiveCD's kernel.
apt install -y \
    linux-tools-common \
    "linux-tools-$KVER" \
    dmidecode \
    fwupd
unset KVER

## General utilities
echo ':: Installing utilities...'
## Hardware tools
apt install -y \
    acpid \
    ethtool \
    fancontrol \
    hdparm \
    iasl \
    i2c-tools \
    lm-sensors \
    lshw \
    mesa-utils \
    nvme-cli \
    pciutils \
    read-edid \
    smartmontools \
    tpm2-tools \
    usbutils
sensors-detect --auto
## Other tools
apt install -y \
    atop \
    cgroup-tools \
    cgroupfs-mount \
    clinfo \
    dstat \
    file \
    gdb \
    htop \
    hwinfo \
    iftop \
    iotop \
    ltrace \
    moreutils \
    ncdu \
    net-tools \
    perf \
    psmisc \
    strace \
    sysstat \

## Install applications
echo ':: Installing applications...'
## Applications that need configuration
[[ $DISTRO -eq 1 ]] && tasksel --new-install
apt install -y popularity-contest
## Common applications
apt install -y cups rsync
## Niche applications
# apt install -y
