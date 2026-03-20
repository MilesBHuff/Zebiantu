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

echo ':: Configuring users...'
## Configure root user
if ! passwd -S root 2>/dev/null | grep -q ' P '; then
    echo 'Please enter a complex password for the root user: '
    passwd
fi
cp /etc/skel/. /root/
## Configure admin user
#    '                                                                                ' ## Guide for wrapping text at 80 characters of width.
echo 'Zebiantu does not implement, modify, or replace the host operating system’s'
echo 'account management system(s). Instead, it invokes — without modification — the'
echo 'native tooling provided by that operating system (e.g., `adduser`) as documented'
echo 'in that system’s official setup instructions. Account creation is performed by'
echo 'the operating system’s native tools and all authentication and identity'
echo 'management are provided and enforced entirely by the operating system’s'
echo 'own mechanisms (not by this script) and remain the responsibility of that'
echo 'operating system and the operator using its tools (i.e., you).'
while true; do
    set -e
    echo
    echo 'Please enter a username for the primary user account.'
    echo '(This account will have `sudo` access.)'
    echo '(Enter nothing if you want to skip this step.)'
    read -r USERNAME
    export USERNAME
    set +e
    if [[ -z "$USERNAME" ]]; then
        break
    fi
    if id "$USERNAME" >/dev/null 2>&1; then
        echo "User '$USERNAME' already exists; please choose a different username." >&2
        continue;
    fi
    if ! adduser "$USERNAME"; then
        echo "Failed to create user; try a different username." >&2
        continue
    fi
    set -e
    usermod -aG sudo "$USERNAME"
    break
done

## Configure mail
echo 'Select "Internet Site" during setup and enter your computer’s domain name.'
apt install -y postfix mailutils
echo 'You can now send local emails to users on this system.'
