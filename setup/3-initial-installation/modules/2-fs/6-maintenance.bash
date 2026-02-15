## Configure trim/discard
echo ':: Scheduling trim...'
systemctl enable fstrim.timer ## Auto-trims everything in /etc/fstab
cat > /etc/systemd/system/zfstrim.service <<'EOF'
[Unit]
Description=Trim ZFS pools
After=zfs.target
[Service]
Type=oneshot
ExecStart=/usr/sbin/zpool trim -a
IOSchedulingClass=idle
EOF
cat > /etc/systemd/system/zfstrim.timer <<'EOF'
[Unit]
Description=Periodic ZFS trim
[Timer]
OnCalendar=*-*-* 03:00
Persistent=true
AccuracySec=1min
[Install]
WantedBy=timers.target
EOF
systemctl enable zfstrim.timer

## Configure scrubs
#TODO

## Configure SMART
#TODO

## Add a memory-freeing script.
echo ':: Adding a way to free memory on-demand...'
cat > '/usr/local/sbin/clean-memory' <<'EOF' && chmod +x '/usr/local/sbin/clean-memory'
#!/bin/sh
set -e
sync
echo 3 > /proc/sys/vm/drop_caches
CEA=$(cat /proc/sys/vm/compact_unevictable_allowed)
[ "$CEA" -ne 1 ] && echo 1 > /proc/sys/vm/compact_unevictable_allowed
echo 1 > /proc/sys/vm/compact_memory
[ "$CEA" -ne 1 ] && echo "$CEA" > /proc/sys/vm/compact_unevictable_allowed
exit 0
EOF
#NOTE: This is used by the hibernation scripts.
