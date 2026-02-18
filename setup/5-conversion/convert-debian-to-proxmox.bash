#!/usr/bin/env bash
set -euo pipefail
function helptext {
    echo "Usage: convert-debian-to-proxmox.bash"
    echo
    echo 'This is a one-shot script that converts Debian into Proxmox.'
    echo 'Luckily for me, someone else already went through the trouble of making this, so this script just calls theirs.'
}
## Instructions: https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie

## Call an upstream script that does it all for us.
SCRIPT=$(mktemp)
curl -O https://raw.githubusercontent.com/MrMasterbay/proxmox-from-scratch/main/little-goblin.sh "$SCRIPT"
chmod +x "$SCRIPT"
# exec "$SCRIPT"
source "$SCRIPT"
rm "$SCRIPT"
unset SCRIPT
#TODO: I don't really agree with all the decisions the writer of the above script made, and would accordingly like to have my own conversion script.

## Proxmox has its own snapshotting functionality; we need to use that instead of Sanoid.
apt purge -y sanoid
rm -f '/etc/sanoid/sanoid.conf' || true
echo 'You need to manually set up snapshotting inside of Proxmox.'
