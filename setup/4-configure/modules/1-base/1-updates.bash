#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script.

## Enable automatic upgrades
echo ':: Automating upgrades...'
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
