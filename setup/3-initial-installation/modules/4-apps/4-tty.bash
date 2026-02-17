#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.
echo ':: Assigning TTYs...'
## The idea is that the host's console runs on TTY10 and all VMs' serial consoles run on TTYs higher than 10.
## A system monitor runs on TTY9.

################################################################################

## The default scrollback is pretty limited; this is more-reasonable.
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE fbcon=scrollback:1024k"

################################################################################

apt install -y btop
## Start `btop` on tty 9 — it's a handy-dandy system monitor with history.
cat > '/etc/systemd/system/btop-on-tty@.service' <<'EOF'
[Unit]
Description=Assign TTY%i to `btop`
After=getty@tty%i.service
Conflicts=getty@tty%i.service
[Service]
TTYPath=/dev/tty%i
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=no
StandardInput=tty
StandardOutput=tty
StandardError=journal
ExecStart=/usr/bin/btop
Restart=always
RestartSec=1
[Install]
WantedBy=multi-user.target
EOF
# systemctl daemon-reload ## Shouldn't run from chroot.
systemctl enable btop-on-tty@9.service #NOTE: No `--now` because we're in a chroot.

################################################################################

## Put the host console at 10.
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE console=tty10"

## Replace it with journald once the system has booted.
## (journald is a superset of the kernel log, and it's interactive.)
cat > '/etc/systemd/system/journald-on-tty@.service' <<'EOF'
[Unit]
Description=Display journald on tty%i
After=multi-user.target
Conflicts=getty@tty%i.service
[Service]
TTYPath=/dev/tty%i
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty
StandardOutput=tty
StandardError=journal
ExecStart=/usr/bin/journalctl -ef -b -o short -p notice
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl enable journald-on-tty@10.service #NOTE: No `--now` because we're in a chroot.

################################################################################

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
printf '\033c' > /dev/tty"$TTY" ## Clears the TTY.
while true; do
    PTS=$(virsh ttyconsole "$VM" 2>/dev/null || true)
    if [ -n "$PTS" ] && [ -e "$PTS" ]; then
        exec socat "/dev/tty$TTY",raw,crnl,echo=0,ixon=0,ixoff=0 "$PTS",raw,echo=0
    fi
    sleep 1
done
EOF

## Service that automates the running of that script.
cat > '/etc/systemd/system/vm-to-tty@.service' <<'EOF'
[Unit]
Description=Assign a VM's serial console to TTY%i
Requires=libvirtd.service
After=libvirtd.service libvirt-guests.service
# After=getty@tty%i.service
# Conflicts=getty@tty%i.service
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
## We don't enable here because we don't have any VMs yet.
