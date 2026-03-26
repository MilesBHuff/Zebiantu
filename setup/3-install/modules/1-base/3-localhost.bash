#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## Configure hostname
echo ':: Configuring hostname...'
read -rp "What unqualified hostname would you like?: " HOSTNAME
# hostname "$HOSTNAME"
# hostname > '/etc/hostname'
hostnamectl set-hostname "$HOSTNAME"

## Configure hosts
echo ':: Configuring hosts...'
cat > '/etc/hosts' <<EOF
## Localhost
127.0.0.1 localhost
::1       localhost

## Custom Addresses
127.0.1.1 $HOSTNAME.home.arpa $HOSTNAME
EOF
