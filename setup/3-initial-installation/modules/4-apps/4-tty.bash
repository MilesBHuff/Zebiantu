#!/usr/bin/env bash
echo ':: Assigning TTYs...'

## Put the host console at 10.
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE console=10"

## Script that attaches guest VM consoles to arbitrary TTYs.
SCRIPT='/usr/local/bin/vm-to-tty'; cat > "$SCRIPT" <<'EOF' && chmod 755 "$SCRIPT"; unset SCRIPT
#!/bin/dash
set -eu
if [ $# -ne 2 ]; then
    echo 'Usage: `vm-to-tty vm_name tty_number`' >&2
    exit 1
fi
VM="$1"; TTY="$2"
shift 2
clear
while true; do
    PTS=$(virsh ttyconsole "$VM" 2>/dev/null || true)
    if [ -n "$PTS" ] && [ -e "$PTS" ]; then
        exec socat "/dev/tty$TTY",raw,echo=0 "$PTS",raw,echo=0
    fi
    sleep 1
done
EOF

## Service that automates the running of that script.
cat > '/etc/systemd/system/vm-to-tty@.service' <<'EOF'
[Unit]
Description=Assign a VM's serial console to a TTY (%i)
Requires=libvirtd.service
After=libvirtd.service libvirt-guests.service
[Service]
ExecStart=/bin/sh -c '/usr/local/bin/vm-to-tty "${1%%:*}" "${1##*:}"' sh %i
Restart=always
RestartSec=1
StandardInput=null
StandardOutput=null
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
# systemctl daemon-reload ## Shouldn't run from chroot.

## The idea is that VMs' serial consoles can own all TTYs higher than 10.
