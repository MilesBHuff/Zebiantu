#!/usr/bin/env bash
function helptext {
    echo "Usage: convert-debian-to-proxmox.bash"
    echo
    echo 'This is a one-shot script that converts Debian into Proxmox.'
    echo 'Luckily for me, someone else already went through the trouble of making this, so this script just calls theirs.'
}
## Instructions: https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie
set -euo pipefail

SCRIPT=$(mktemp)
curl -O https://raw.githubusercontent.com/MrMasterbay/proxmox-from-scratch/main/little-goblin.sh "$SCRIPT" #TODO: I don't really agree with all their decisions, and would accordingly like to have my own conversion script.
chmod +x "$SCRIPT"
# exec "$SCRIPT"
source "$SCRIPT"
rm "$SCRIPT"
unset SCRIPT
