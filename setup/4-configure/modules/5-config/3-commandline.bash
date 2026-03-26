#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script.

echo ':: Additional configurations...'
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE page_alloc.shuffle=1" ## Easy but small security win.

## Set kernel commandline
echo ':: Setting kernel commandline...'
echo "$KERNEL_COMMANDLINE" > "$ENV_KERNEL_COMMANDLINE_DIR/commandline.txt"
"$ENV_KERNEL_COMMANDLINE_DIR/set-commandline" ## Sorts, deduplicates, and saves the new commandline.
update-initramfs -u
