#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## Get input
declare -i YES_VM=-1
while true; do
    read -rp 'Will this OS run VMs? (y/n)' ANSWER
    case "$ANSWER" in
        y) YES_VM=1; break ;;
        n) YES_VM=0; break ;;
    esac
    unset ANSWER
done
declare -i YES_CONTAINER=-1
while true; do
    read -rp 'Will this OS run containers? (y/n)' ANSWER
    case "$ANSWER" in
        y) YES_CONTAINER=1; break ;;
        n) YES_CONTAINER=0; break ;;
    esac
    unset ANSWER
done

## Do the thing
apt install -y sanoid
SANOID_CONF='/etc/sanoid/sanoid.conf'
cat > "$SANOID_CONF" <<EOF
################################################################################
## Templates

## Things that should not be snapshotted.
[none]
    recursive = yes
    autosnap  = no
    autoprune = no
    snapshot_prefix = snapshot_

## Things that should not be snapshotted but do need to be backed-up.
[backup]
    hourly  =  0
    daily   =  0
    weekly  =  1
    monthly =  3
    yearly  =  0
    recursive = yes
    autosnap  = yes
    autoprune = yes
    snapshot_prefix = snapshot_

## Things that only need just enough snapshotting to ensure continued operations.
## Enough hours to catch mistakes/attacks over the course of a waking day.
## Enough days to catch mistakes/attacks over a long weekend.
## Enough weeks to just barely cover the recent past.
## Enough months to guarantee the next off-site rotation is covered even if it is delayed by a long vacation.
[min]
    hourly  = 18
    daily   =  5
    weekly  =  2
    monthly =  3
    yearly  =  0
    recursive = yes
    autosnap  = yes
    autoprune = yes
    snapshot_prefix = snapshot_

## Things that a user is actively working on.
## Enough hourly snapshots to, at the end of today's waking hours, catch a mistake made at the beginning of yesterday's waking hours.
## Two weeks of daily snapshots is a common choice for auto-clearing trash because by this point, things have usually safely left your mental horizon.
## A quarter of weekly snapshots for good measure.
## A little over a year of monthly snapshots, just in case something gets deleted and a need for it only arises 12 months later.
[max]
    hourly  = 36
    daily   = 14
    weekly  = 13
    monthly = 13
    yearly  =  0
    recursive = yes
    autosnap  = yes
    autoprune = yes
    snapshot_prefix = snapshot_

################################################################################
## Datasets

[$ENV_POOL_NAME_OS/OS]
    use_template = min
[$ENV_POOL_NAME_OS/OS/junk]
    use_template = none

[$ENV_POOL_NAME_OS/data]
    use_template = min
EOF
[[ $YES_VM -eq 1 ]] && cat >> "$SANOID_CONF" <<EOF
[$ENV_POOL_NAME_OS/data/vm]
    use_template = min
EOF
[[ $YES_CONTAINER -eq 1 ]] && cat >> "$SANOID_CONF" <<EOF
[$ENV_POOL_NAME_OS/data/containers]
    use_template = backup
EOF
systemctl enable 'sanoid.timer'
