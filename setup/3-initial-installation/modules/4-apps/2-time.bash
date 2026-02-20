#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## See here for documentation: https://github.com/MilesBHuff/NixOS/blob/master/persist/etc/chrony/chrony.conf
cat > '/etc/chrony/chrony.conf' << 'EOF'
pool time.cloudflare.com nts iburst
# minsources 3
dumpdir     /var/lib/chrony/dump/
logdir      /var/log/chrony/logs/
ntsdumpdir  /var/lib/chrony/ntsdump/
driftfile   /var/lib/chrony/drift
# hwclockfile /etc/adjtime
rtcfile     /var/lib/chrony/rtc
dumponexit
lock_all
nocerttimecheck 1
rtcautotrim 1
makestep 0.1 4
rtconutc
leapsectz UTC
hwtimestamp *
maxdistance 1.5
maxupdateskew 250
EOF
echo 'You should manually replace `time.cloudflare.com` with your local timeserver and change `pool` to `server`.'
echo 'If your local timeserver does not support NTS, make sure you also change `nts` to `ntp`.'
echo 'I recommend configuring your local timeserver to smear leap seconds; else, you risk occasional random Y2K events until 2035.'
