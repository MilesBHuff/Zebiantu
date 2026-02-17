#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## Configure hostname
echo ':: Configuring hostname...'
read -rp "What unqualified hostname would you like?: " HOSTNAME
# hostname "$HOSTNAME"
# hostname > '/etc/hostname'
hostnamectl set-hostname "$HOSTNAME"
sed -i '/^127\.0\.1\.1 /d' '/etc/hosts'
idempotent_append "127.0.1.1 $HOSTNAME" '/etc/hosts'

## Configure the system
echo ':: Configuring system...'
apt install -y locales
dpkg-reconfigure locales
apt install -y console-setup
read -rp "Note: 8x16 is considered kinda the standard size. Bold is easiest to read. VGA is probably your best bet. Press 'Enter' to continue. " _; unset _
dpkg-reconfigure console-setup
dpkg-reconfigure keyboard-configuration
dpkg-reconfigure tzdata

## Set up /etc/skel
echo ':: Creating user configs...'
apt install -y tmux
echo 'set -g status-position top' > /etc/skel/.tmux.conf
idempotent_append 'shopt -q login_shell && [[ $- == *i* ]] && command -v tmux >/dev/null && [[ ! -n "$TMUX" ]] && exec tmux' '/etc/skel/.bashrc'

## Configure users
echo ':: Configuring users...'
if ! passwd -S root 2>/dev/null | grep -q ' P '; then
    echo 'Please enter a complex password for the root user: '
    passwd
fi
cp /etc/skel/. /root/
read -rp "Please enter a username for your personal user: " USERNAME
id "$USERNAME" >/dev/null 2>&1 || adduser "$USERNAME"
export USERNAME
