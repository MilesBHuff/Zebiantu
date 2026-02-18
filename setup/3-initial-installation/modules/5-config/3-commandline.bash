#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.
echo ':: Additional configurations...'
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE page_alloc.shuffle=1" ## Easy but small security win.

## Set kernel commandline
echo ':: Setting kernel commandline...'
mkdir -p "$ENV_KERNEL_COMMANDLINE_DIR"
echo "$KERNEL_COMMANDLINE" > "$ENV_KERNEL_COMMANDLINE_DIR/commandline.txt"
echo '#!/bin/sh' > "$ENV_KERNEL_COMMANDLINE_DIR/set-commandline"
echo 'BOOTFS=$(zpool get -Ho value bootfs '"$ENV_POOL_NAME_OS"')' > "$ENV_KERNEL_COMMANDLINE_DIR/set-commandline"
cat >> "$ENV_KERNEL_COMMANDLINE_DIR/set-commandline" <<'EOF'
COMMANDLINE="$(awk '{for(i=1;i<=NF;i++){t=$i;if(index(t,"=")){split(t,a,"=");m[a[1]]=t}else m[t]=t}}END{for(k in m)printf "%s ",m[k]}' /etc/zfsbootmenu/commandline/commandline.txt)" ## AI code that deduplicates like keys, keeping the rightmost instances.
zfs set org.zfsbootmenu:commandline="$COMMANDLINE" "$BOOTFS"
zfs get org.zfsbootmenu:commandline "$BOOTFS"
EOF
export ENV_KERNEL_COMMANDLINE_DIR
"$ENV_KERNEL_COMMANDLINE_DIR/set-commandline"
update-initramfs -u
