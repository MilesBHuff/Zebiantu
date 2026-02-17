#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## Install build tools
echo ':: Installing build tools...'
apt install -y build-essential pkg-config

## Install Linux
echo ':: Installing Linux...'
case $DISTRO in
    1) apt install -y -t "$DEBIAN_VERSION-backports" linux-image-amd64 linux-headers-amd64 dkms ;;
    2) apt install -y -t "$UBUNTU_VERSION-backports" linux-image-generic linux-headers-generic dkms ;;
esac

## Install initramfs
echo ':: Installing initramfs...'
apt install -y initramfs-tools

## Install important but potentially missing compression algorithms and tooling
echo ':: Installing compressiony things...'
apt install -y gzip lz4 lzop unrar unzip zip zstd
idempotent_append 'lz4' '/etc/initramfs-tools/modules'
idempotent_append 'lz4_compress' '/etc/initramfs-tools/modules'

## Install systemd
echo ':: Installing systemd...'
apt install -y systemd

## Install MAC
echo ':: Enabling Mandatory Access Control...'
apt install -y apparmor apparmor-utils apparmor-notify apparmor-profiles apparmor-profiles-extra
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE apparmor=1 security=apparmor"
