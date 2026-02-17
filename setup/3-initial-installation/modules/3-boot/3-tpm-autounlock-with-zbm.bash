#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.
## Set up auto-unlock via TPM.
##
## The main thing that needs to be done for this is a custom ZBM that contains the sealed key and instructions for how to unseal it. We don't actually have to go through the trouble of storing the sealed key in the initramfs because the system can auto-load the raw key from /etc/zfs/keys after ZBM unlocks it.
## If the ESP ever dies or gets corrupted, the recovery path is pretty simple: put vanilla ZBM on a flashdrive, temp disable SB, boot to flashdrive, manually unlock zpool, boot OS, regenerate custom ZBM, reboot, remove flashdrive, reenable SB.
##
## Whether you actually want this depends on what you're doing.
## + An edge router that requires manual intervention on every boot is not a good edge router; for this, TPM auto-unlock is required for proper function.
## - A NAS that auto-unlocks is guaranteed to someday be able to give your data to an attacker for free, because given enough time there will always eventually come to be some root escalation bug that is accessible to someone with physical access.

## Make sure we actually have a TPM.
if [[ ! -e /dev/tpmrm0 ]]; then
    echo "ERROR: No TPM detected!"
    exit 5
fi

## Install requisites
apt install -y clevis clevis-tpm2 tpm2-tools

## Clear the TPM
#NOTE: Apparently there aren't great ways to do this from the OS; it should be done at firmware level.

## Seal to TPM
KEY="/etc/zfs/keys/$ENV_POOL_NAME_OS.key"
BLOB_DIR='/etc/zfsbootmenu/keys'
BLOB="$BLOB_DIR/$ENV_POOL_NAME_OS.jwe"
install -dm 0755 "$BLOB_DIR"
clevis encrypt tpm2 '{"pcr_ids":"7"}' < "$KEY" > "$BLOB"
unset KEY
chmod 0600 "$BLOB"
sync
clevis decrypt < "$BLOB" | head -n 1

## Ensure ZBM is capable of unsealing the key.
install -dm 0755 /etc/zfsbootmenu/dracut.conf.d
cat > /etc/zfsbootmenu/dracut.conf.d/50-tpm-unseal.conf <<EOF && chmod 644 /etc/zfsbootmenu/dracut.conf.d/50-tpm-unseal.conf #AI
install_items+=" $BLOB /usr/bin/clevis /usr/bin/jose /usr/lib/clevis/ /usr/libexec/clevis/ "
EOF

## Make ZBM unseal the key.
install -dm 0755 /etc/zfsbootmenu/hooks/load-key.d
cat > /etc/zfsbootmenu/hooks/load-key.d/10-tpm-unseal <<EOF && chmod 755 /etc/zfsbootmenu/hooks/load-key.d/10-tpm-unseal #AI
#!/bin/sh
set -eu
## ZBM provides these (see zfsbootmenu(7)): ZBM_LOCKED_FS, ZBM_ENCRYPTION_ROOT
BLOB="$BLOB"
TMP='/run/zfskey.pass'
command -v clevis >/dev/null 2>&1 || exit 0
[ -s "\$BLOB" ] || exit 0
umask 077
rm -f "\$TMP"
if ! clevis decrypt < "\$BLOB" > "\$TMP" 2>/dev/null; then
    rm -f "\$TMP"
    exit 0
fi
[ -f "\$ZBM_ENCRYPTION_ROOT" ] || exit 1
zfs load-key -L "file://\$TMP" "\$ZBM_ENCRYPTION_ROOT" >/dev/null 2>&1 || true
rm -f "\$TMP"
exit 0
EOF

## Update ZBM
generate-zbm
