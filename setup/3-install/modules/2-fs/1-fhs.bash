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
