#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.
echo ':: Modifying filesystem hierarchy...'

## `/boot` contains sensitive things; it should not be world-readable.
chmod 700 '/boot'

## This helps reflect dataset inheritance — filesystem `/root` lives under dataset `/home`.
if [[ ! -L '/home/root' ]]; then
    [[ ! -d '/root' ]] && mkdir '/root'
    ln -sTv '/root' '/home/root'
fi

## `/var/www` needs to be moved to `/srv` so that it is treated the same as other web services.
if [[ ! -L '/var/www' ]]; then
    [[ ! -d '/var/www' ]] && mkdir '/var/www'
    [[ ! -d '/srv/www' ]] && mkdir '/srv/www'
    rsync -a --remove-source-files '/var/www/' '/srv/www/'
    ln -sTv '/srv/www' '/var/www'
fi

## Some items in `/var` need to be tied to system snapshots.
## The criteria for inclusion is whether a rollback without the item would render the system's state inconsistent.
VARKEEP_DIR='/varlib'
mkdir -p "$VARKEEP_DIR"
if [[ -d "$VARKEEP_DIR" ]]; then
    declare -a VARKEEP_DIRS=('lib/apt' 'lib/dkms' 'lib/dpkg' 'lib/emacsen-common' 'lib/sgml-base' 'lib/ucf' 'lib/xml-core') # 'lib/apt/states' 'lib/shells'
    for DIR in "${VARKEEP_DIRS[@]}"; do
        if [[ ! -L "/var/$DIR" ]]; then
            [[ ! -d "/var/$DIR" ]] && mkdir "/var/$DIR"
            mv -f "/var/$DIR" "$VARKEEP_DIR/"
            ln -sTv "$VARKEEP_DIR/$DIR" "/var/$DIR"
        fi
    done
    declare -a VARKEEP_FILES=() #WARN: The following files' associated applications recreate them, meaning that any symlinks are be deleted and replaced: 'lib/apt/extended_states' 'lib/shells.state'
    for FILE in "${VARKEEP_FILES[@]}"; do
        if [[ ! -L "/var/$FILE" ]]; then
            [[ ! -f "/var/$FILE" ]] && continue
            install -D "/var/$FILE" "$VARKEEP_DIR/$FILE"
            rm -f "/var/$FILE"
            ln -sTv "$VARKEEP_DIR/$FILE" "/var/$FILE"
        fi
    done
fi
unset VARKEEP_DIR
