#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.
#NOTE: If you want these tasks to run at a specific time, you must override them in a system-specific install script.

## Configure trim/discard
echo ':: Configuring trim...'
systemctl enable fstrim.timer ## Auto-trims everything in /etc/fstab
#NOTE: `zfstrim.[service|timer]` were designed to be minimally divergent from `fstrim.[service|timer]`.
cat > /etc/systemd/system/zfstrim.service <<'EOF'
[Unit]
Description=Trim ZFS pools
After=zfs.target
ConditionVirtualization=!container
[Service]
Type=oneshot
ExecStart=/usr/sbin/zpool trim -a
IOSchedulingClass=idle
EOF
cat > /etc/systemd/system/zfstrim.timer <<'EOF' && systemctl enable zfstrim.timer
[Unit]
Description=Periodic ZFS trim
ConditionVirtualization=!container
ConditionPathExists=!/etc/initrd-release
[Timer]
OnCalendar=weekly
AccuracySec=1h
Persistent=true
RandomizedDelaySec=6000
[Install]
WantedBy=timers.target
EOF

## Configure scrubs
echo ':: Configuring scrubs...'
cp -a '/etc/systemd/system/zfs-scrub-monthly@.timer' '/etc/systemd/system/zfs-scrub@.timer' &&\
    systemctl enable "zfs-scrub@$ENV_POOL_NAME_OS.timer"

## Configure SMART
echo ':: Configuring SMART...'
mv '/etc/smartd.conf' '/etc/smartd.conf.bak'
cat > '/etc/smartd.conf' << 'EOF' && smartd -q onecheck && systemctl enable smartmontools #NOTE: No `--now` because we're in a chroot.
## See `man 5 smartd.conf` for documentation.
##
## DEVICESCAN: Apply to all devices.
## -a: Monitor all SMART attributes.
## -o on: Enable automatic offline tests.
## -S on: Enable autosave
## -W x,y,z: Enable alerts for various temperatures: Every time a drive changes by x°C from the last report, and every time a drive passes y°C or z°C.
## -m user: Send user an email for alerts.
##
## Temperature delta doesn't matter too much to me as long as it's within range, so I won't alert on it.
## 45°C is about the point at which HDD and battery life (for PLP drives) noticeably start to decline, so we should notify if we get near to it.
## 60°C is the rated limit for SeaGate Exos drives. We want the critical notification well-before we reach the danger zone.
##
## Note that I am not scheduling any short/long tests here: this is because I want schedules to be per-drive, to avoid contention.
##
DEVICESCAN -ao on -S on -W 0,43,50 -m root
EOF
## Short tests (not enabled by default)
cat > '/etc/systemd/system/smart-short@.service' << 'EOF'
[Unit]
Description=SMART short test on %i
Documentation=man:smartctl(8)
[Service]
Type=oneshot
ExecStart=/usr/sbin/smartctl -t short /dev/disk/by-id/%i
EOF
cat > '/etc/systemd/system/smart-short@.timer' << 'EOF'
[Unit]
Description=Periodic SMART short test for %i
[Timer]
OnCalendar=weekly
AccuracySec=1h
Persistent=true
RandomizedDelaySec=6000
[Install]
WantedBy=timers.target
EOF
## Long tests (not enabled by default)
cat > '/etc/systemd/system/smart-long@.service' << 'EOF'
[Unit]
Description=SMART long test on %i
Documentation=man:smartctl(8)
[Service]
Type=oneshot
ExecStart=/usr/sbin/smartctl -t long /dev/disk/by-id/%i
EOF
cat > '/etc/systemd/system/smart-long@.timer' << 'EOF'
[Unit]
Description=Periodic SMART long test for %i
[Timer]
OnCalendar=weekly
AccuracySec=1h
Persistent=true
RandomizedDelaySec=6000
[Install]
WantedBy=timers.target
EOF

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
