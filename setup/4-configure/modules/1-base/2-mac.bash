#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script.

## Install MAC
echo ':: Enabling Mandatory Access Control...'
apt install -y apparmor apparmor-utils apparmor-notify apparmor-profiles apparmor-profiles-extra
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE apparmor=1 security=apparmor"
