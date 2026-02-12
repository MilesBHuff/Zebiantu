#!/usr/bin/env bash
## Disable or (if impossible to disable) adjust various compressions to save CPU (ZFS does compression for us extremely cheaply, and space is very plentiful on the OS drives.)
echo ':: Tweaking various compression settings...'
FILE='/etc/initramfs-tools/initramfs.conf'
cat "$FILE" | sed -r 's/^(COMPRESS)=.*/\1=zstd/' | sed -r 's/^# (COMPRESS_LEVEL)=.*/\1=0/' > "$FILE.new" ## I tested; `zstd-0` beats `lz4-0` at both speed and ratio here.
mv -f "$FILE.new" "$FILE"
for FILE in /etc/logrotate.conf /etc/logrotate.d/*; do
    if grep -Eq '(^|[^#y])compress' "$FILE"; then
        cat "$FILE" | sed -r 's/(^|[^#y])(compress)/\1#\2/' > "$FILE.new"
        mv "$FILE.new" "$FILE"
    fi
done
unset FILE

## Limit log size
echo ':: Limiting log sizes...'
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/max-size.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=256M
RuntimeMaxUse=128M
EOF
