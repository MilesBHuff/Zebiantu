#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script.

## Configure mail
echo 'Select "Internet Site" during setup and enter your computer’s domain name.'
apt install -y postfix mailutils
echo 'You can now send local emails to users on this system.'

## Set up /etc/skel
echo ':: Specifying user defaults...'
apt install -y tmux
echo 'set -g status-position top' > /etc/skel/.tmux.conf
idempotent_append 'shopt -q login_shell && [[ $- == *i* ]] && command -v tmux >/dev/null && [[ ! -n "$TMUX" ]] && exec tmux' '/etc/skel/.bashrc'
cp /etc/skel/. /root/

echo ':: Configuring users...'
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
## Configure root user
#TODO: Prompt the operator and ask if they would like to disable the root user.
