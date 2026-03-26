#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## Configure the system
echo ':: Configuring system...'
apt-get install -y locales tzdata keyboard-configuration console-setup
dpkg-reconfigure locales
dpkg-reconfigure tzdata
dpkg-reconfigure keyboard-configuration
echo
echo 'Note: 8x16 is considered kinda the standard size. Bold is easiest to read. VGA is probably your best bet.'
read -rp "Press 'Enter' to continue. " _; unset _
dpkg-reconfigure console-setup

echo ':: Configuring root...'
## Configure root user
if ! passwd -S root 2>/dev/null | grep -q ' P '; then
    echo 'Please enter a complex password for the root user: '
    passwd
fi
