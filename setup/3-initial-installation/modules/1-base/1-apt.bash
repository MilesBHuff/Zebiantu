#!/usr/bin/env bash

## Configure apt
echo ':: Configuring apt...'
case $DISTRO in
    1) cat > /etc/apt/sources.list <<EOF ;;
deb      https://deb.debian.org/debian/                $DEBIAN_VERSION                   main contrib non-free-firmware non-free
deb-src  https://deb.debian.org/debian/                $DEBIAN_VERSION                   main contrib non-free-firmware non-free

deb      https://deb.debian.org/debian/                $DEBIAN_VERSION-backports         main contrib non-free-firmware non-free
deb-src  https://deb.debian.org/debian/                $DEBIAN_VERSION-backports         main contrib non-free-firmware non-free

deb      https://deb.debian.org/debian/                $DEBIAN_VERSION-backports-sloppy  main contrib non-free-firmware non-free
deb-src  https://deb.debian.org/debian/                $DEBIAN_VERSION-backports-sloppy  main contrib non-free-firmware non-free

deb      https://security.debian.org/debian-security/  $DEBIAN_VERSION-security          main contrib non-free-firmware non-free
deb-src  https://security.debian.org/debian-security/  $DEBIAN_VERSION-security          main contrib non-free-firmware non-free

deb      https://deb.debian.org/debian/                $DEBIAN_VERSION-updates           main contrib non-free-firmware non-free
deb-src  https://deb.debian.org/debian/                $DEBIAN_VERSION-updates           main contrib non-free-firmware non-free
EOF
    2) cat > /etc/apt/sources.list.d/official-package-repositories.list <<EOF
deb https://archive.ubuntu.com/ubuntu/     $UBUNTU_VERSION            main restricted universe multiverse
#deb https://archive.canonical.com/ubuntu/ $UBUNTU_VERSION            partner
deb https://archive.ubuntu.com/ubuntu/     $UBUNTU_VERSION-updates    main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/     $UBUNTU_VERSION-backports  main restricted universe multiverse
deb https://security.ubuntu.com/ubuntu/    $UBUNTU_VERSION-security   main restricted universe multiverse
EOF
    set +e
    ${EDITOR:-nano} /etc/apt/sources.list.d/*
    set -e
    ;;
esac

## Get our packages up-to-date
echo ':: Upgrading packages...'
apt update
apt full-upgrade -y

## Enable automatic upgrades
echo ':: Automating upgrades...'
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
