#!/usr/bin/env bash
set -euo pipefail
function helptext {
    echo "Usage: convert-debian-to-proxmox.bash"
    echo
    echo 'This is a one-shot script that converts Debian into Proxmox.'
    echo 'Luckily for me, someone else already went through the trouble of making this, so this script just calls theirs.'
}
## Instructions: https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie
#NOTE: I don't really agree with all the decisions the writer of the upstream script made, so we have to override it in a few spots.

## Proxmox has its own snapshotting functionality; we need to use that instead of Sanoid.
apt purge -y sanoid
rm -f '/etc/sanoid/sanoid.conf' || true
echo 'You need to manually set up snapshotting inside of Proxmox.'

## We need to modify, back up, and later restore our current sources.list
cp -a '/etc/apt/sources.list' '/etc/apt/sources.list.bak'
cat >> '/etc/apt/sources.list.bak' <<'EOF'

deb      https://download.proxmox.com/debian/pve       trixie                            pve-no-subscription
EOF

## Call an upstream script that does it all for us.
SCRIPT=$(mktemp)
URL='https://raw.githubusercontent.com/MrMasterbay/proxmox-from-scratch/main/little-goblin.sh'
HASH='8a4d261f94a10564587603ec38ea05fac2c66100fac0a5dc40e7b062fed18fdd'
curl "$URL" -o "$SCRIPT"
unset URL
if [[ $(sha256sum "$SCRIPT" | awk '{print $1}') != "$HASH" ]]; then
    echo "$0: '$SCRIPT' has an invalid checksum." >&2
    rm -f "$SCRIPT"
    exit 50
fi
unset HASH
chmod +x "$SCRIPT"
read -r 'We will now execute the conversion script. When it completes, do NOT allow it to restart your system; we need to run some things after it finishes.'
("$SCRIPT")
rm -f "$SCRIPT"
unset SCRIPT

## Restore customized files
mv -f '/etc/apt/sources.list.bak' '/etc/apt/sources.list'
apt update -y
[[ -f '/etc/hosts.backup' ]] && mv -f '/etc/hosts.backup' '/etc/hosts' ## Shouldn't happen, since the conversion script only creates this file if there's no FQDN, and we definitely set one.

## Done
exit 0
