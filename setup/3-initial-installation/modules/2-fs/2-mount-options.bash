#!/usr/bin/env bash

## Enforce mount options
echo ':: Changing default mount options...'
## ZFS does not provide properties for all of the mount options it supports (like `lazytime`; see https://github.com/openzfs/zfs/issues/9843), so we have to specify it manually when mounting datasets or monkeypatch `zfs` to do it by default.
## Linux's default mount options include `relatime` and lack `lazytime`, which is suboptimal for performance and longevity. The only way to change the defaults is to monkeypatch `mount`.
## A lot of system mounts explicitly declare `relatime` when nothing in them actually uses atimes. These need manual correction.
BASENAME=remount-options
SCRIPT="/usr/local/sbin/.$BASENAME"

SERVICE="/etc/systemd/system/$BASENAME-normal.service"
cat > "$SERVICE" <<EOF
[Unit]
Description=Retroactively apply mount options to all non-zfs mounts.
After=local-fs.target
# Requires=local-fs.target
[Service]
Type=oneshot
ExecStart=$SCRIPT mount
[Install]
WantedBy=multi-user.target
EOF
systemctl enable "$SERVICE"

SERVICE="/etc/systemd/system/$BASENAME-zfs.service"
cat > "$SERVICE" <<EOF
[Unit]
Description=Retroactively apply mount options to all zfs mounts.
After=zfs-mount.service
Requires=zfs-mount.service
[Service]
Type=oneshot
ExecStart=$SCRIPT zfs
[Install]
WantedBy=multi-user.target
EOF
systemctl enable "$SERVICE"

cat > "$SCRIPT" <<'EOF'; chmod +x "$SCRIPT"
#!/bin/sh
AWK_SCRIPT='{ print $2, $4 }'
[ "$1" = 'mount' ] && AWK_SCRIPT='$3!="zfs" '"$AWK_SCRIPT" ||\
[ "$1" = 'zfs'   ] && AWK_SCRIPT='$3=="zfs" '"$AWK_SCRIPT"
awk "$AWK_SCRIPT" /proc/self/mounts | while read -r MOUNT_PATH MOUNT_OPTS; do
    REMOUNT_OPTS=''
    case ",$MOUNT_OPTS," in
        *,lazytime,*|*,sync,*|*,ro,*) ;; #FIXME: There is probably no point in enabling `lazytime` on RAM-based filesystems.
        *) REMOUNT_OPTS="$REMOUNT_OPTS,lazytime" ;;
    esac
    case ",$MOUNT_OPTS," in
        # *,noatime,*|*,relatime,*|*,atime,*) ;;
        *,noatime,*|*,atime,*) ;; ## A lot of filesystems are explicitly mounted with relatime for no reason, and accordingly need to be overridden -- This means that filesystems that *do* need atimes have to set `atime`, not `relatime`...
        *) REMOUNT_OPTS="$REMOUNT_OPTS,noatime" ;;
    esac
    if [ -n "$REMOUNT_OPTS" ]; then
        mount -o "remount$REMOUNT_OPTS" "$MOUNT_PATH"
    fi
done
exit 0
EOF

SCRIPT=/usr/local/sbin/mount
cat > "$SCRIPT" <<'EOF'; chmod +x "$SCRIPT"
#!/bin/sh
exec /usr/bin/mount -o noatime,lazytime "$@"
EOF
## Note to code reviewers: `-o` can be passed multiple times, and later values override prior ones.

SCRIPT=/usr/local/sbin/zfs
cat > "$SCRIPT" <<'EOF'; chmod +x "$SCRIPT"
#!/bin/sh
[ "$1" != mount ] && exec /usr/sbin/zfs "$@"
shift
exec /usr/sbin/zfs mount -o lazytime "$@"
EOF

unset BASENAME SCRIPT SERVICE
