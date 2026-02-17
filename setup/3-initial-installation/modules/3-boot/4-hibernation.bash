#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.
################################################################################
##
## **Blockers:**
echo 'ZFS currently DOES NOT SUPPORT HIBERNATION, even hibernation to swap outside of ZFS.' >&2
echo 'It is safe to latently enable hibernation in your configurations, but DO NOT USE IT until ZFS supports it!' >&2
echo 'Additionally, because of this: the hibernation that this script enables has not been tested.' >&2
echo 'Proceed at your own risk.' >&2
echo
##
## **Requirements:**
## * You must be on a kernel that supports zram.
## * You must use zram swap as your sole source of swap.
## * You must be using encrypted ZFS for your operating system's root.
## * You have the `clean-memory` script.
## All of the above are true in this repo.
##
## **Overview:**
## 'Hibernation is a useful but universally overlooked feature in the server space:
## '* In the event of a prolonged power-outage, a system connected to a UPS can hibernate instead of powering off.
## '  At the end of the outage, this system can then restore to its prior state.
## '  This can be much faster and much-less-disruptive than a hard reboot.
## '* Hibernation is also, obviously, very useful on a laptop:
## '  The system can hibernate before the battery dies, thus allowing resumption without a reboot once power is resupplied.
## '  That means you no longer ever have to worry about finishing up and closing everything before your laptop dies.
echo 'Hibernation is not appropriate for all situations:'
echo '* On systems with large amounts of RAM, hibernation may be slower than shutting down and cold-booting.'
echo '    * If hibernation takes a particularly long time, your UPS may die before hibernation finishes.'
echo '* Systems with large RAM may find that the reservation required to support hibernation may eat far too much storage to be worthwhile.'
echo '    * In extreme cases, it may be physically impossible to make a reservation large-enough to support hibernation.'
echo '* Hibernation can cause weird issues with some applications, especially in a virtualization context.'
echo
echo 'Only use hibernation where it makes sense and where you can test and confirm it does not cause problems for your particular workload.'
declare -i CONTINUE=-1
while read -rp 'Enable hibernation? (y/n) ' ANSWER; do
    case "$ANSWER" in
        y) CONTINUE=1; break ;;
        n) CONTINUE=0; break ;;
    esac
done
##
## **Etymology:**
## Windows, unlike Linux, properly distinguishes the roles of the on-disk memory cache ("pagefile") and hibernation cache ("hiberfile").
## This script introduces that distinction to Linux.
## As swap devices in a ZFS system are nigh-necessarily zvols, I have taken to calling ours a "hibervol", by analogy.
##
## **Whys:**
## Why bother with this? Why not just have permanent on-disk swap all the time? Why not just not have swap at all?
## * Swap on ZFS is a bad idea for normal operation:
##   * System resource contention can result in *bad* scenarios where there aren't enough resources to properly steward the zvol that swap is located on at the same time as the system needs to swap/unswap in order to function.
##   * zvol swap is not great; swapfiles are even worse.
## * Swap partitions are extremely inelegant:
##   * They must be encrypted or an attacker can read the full contents of your memory from your disk.
##     * On an array, this means encrypted LUKS atop LVM OR several independent LUKS partitions; either way, you have to configure your initramfs to unlock them or you have to manually enter passwords.
##   * They kill the beautiful dream of having ZFS be the one true master of all storage.
##   * They prevent ZFS from running in whole-disk mode.
##   * They significantly complicate the addition of new disks to an array.
## * For 99.9% of a computer's operational life, having on-disk swap is not only unnecessary: It's actively harmful.
##   * The only time swap needs durability is during hibernation.
##   * Swapping to/from compressed RAM is *ludicrously* faster than swapping to/from durable storage.
##   * Swapping to/from durable storage competes with normal I/O, thus degrading normal I/O performance.
##   * ZFS performance significantly degrades when there is not much freespace. A permanent capacity loss equal to total RAM can be *substantial*, and thereby pose a significant reduction to performance in a near-full pool.
##   * Significantly reducing the space available to ZFS 99.9% of the time to simplify 0.01% of the time is a bad trade.
## * Having no swap at all means you don't have any way to avert an OOM killer when the kernel excessively overcommits memory. Given the ease with which zram swap can be enabled, I consider it to be senseless/reckless to run swapless.
##
## **Risks:**
## * If something goes wrong and hibernation or resume fails, you have the effects of a sudden system crash.
## * Some applications may not handle hibernation and clock changes gracefully.
## * If you have a *ton* of RAM, you may not have time to hibernate before your UPS runs out of battery.
##
################################################################################
if [[ $CONTINUE -eq 1 ]]; then
    SWAP_NAME="hiberswap"
    ZVOL_NAME="hibervol"
    ZVOL_LOCATION="$ENV_POOL_NAME_OS/$ZVOL_NAME"

    ############################################################################
    ##
    ## **Preparation:**
    ## Set a hard quota on the OS zpool's root dataset that preserves an amount of space equal to the total amount of installed RAM (as this is the largest hibervol our algorithm will create).
    ## Set `resume=` on the kernel commandline.
    ## Ensure that initramfs triggers `systemd-hibernate-generator` after pool unlock and import. (TODO: not sure how to check)
    ##
    ############################################################################

    ## Every boot, set a new quota on the OS zpool that guarantees enough room to swap.
    PREP_NAME='set-quota-for-hibernation'
    PREP_SCRIPT="/usr/local/sbin/$PREP_NAME"
    cat > "$PREP_SCRIPT" <<EOF && chmod +x "$PREP_SCRIPT"
#!/bin/sh
set -eu
#WARN: Do not run this on systems without sufficient storage to fit the full contents of RAM!
ZPOOL_DATASET="$ENV_POOL_NAME_OS" ## All other datasets are children of this, and so should be affected by any quota set here.
ZFS_BIN="$(command -v zfs)"
## Remove the current quota, if any.
"\$ZFS_BIN" set 'quota=off' "\$ZPOOL_DATASET"
## Get total size of pool.
## (Using used+avail instead of raw total, since this factors out deadweight filesystem losses that would have undersized the quota.)
USED="\$(\$ZFS_BIN get -Hpo value used "\$ZPOOL_DATASET")"
AVAIL="\$(\$ZFS_BIN get -Hpo value available "\$ZPOOL_DATASET")"
if [ -z "\$USED" -o -z "\$AVAIL" ]; then
    echo "\$0: Could not read size of \`\$ZPOOL_DATASET\`." >&2
    exit 1
fi
TOTAL_STORAGE=\$((USED + AVAIL))
unset USED AVAIL
## Get total size of RAM.
TOTAL_RAM="\$(awk '/^MemTotal:/ {print \$2}' /proc/meminfo)" #AI: MemTotal is reported in kB (actually KiB) in /proc/meminfo.
if [ -z "\$TOTAL_RAM" ]; then
    echo "\$0: Could not read \`MemTotal\` from \`/proc/meminfo\`." >&2
    exit 1
fi
TOTAL_RAM=\$((TOTAL_RAM * 1024))
## Calculate the quota.
QUOTA=\$((TOTAL_STORAGE - TOTAL_RAM)) ## No need to guard against negatives — you'd have to ignore multiple warnings and lack common sense to enable a RAM reservation on a system without enough space to comfortably fit the contents of RAM on-disk.
unset TOTAL_STORAGE TOTAL_RAM
## Apply the quota.
exec "\$ZFS_BIN" set "quota=\$QUOTA" "\$ZPOOL_DATASET"
EOF
    PREP_SERVICE="/etc/systemd/system/$PREP_NAME.service"
    cat > "$PREP_SERVICE" <<EOF
[Unit]
Description=Set a quota on \`$ENV_POOL_NAME_OS\` that ensures the possibility of hibernation.
DefaultDependencies=no
Requires=zfs-import.target
After=zfs-import.target
ConditionPathExists=/proc/meminfo
[Service]
Type=oneshot
ExecStart=-$PREP_SCRIPT
[Install]
WantedBy=sysinit.target
EOF
    systemctl enable "$PREP_NAME" #NOTE: No `--now` because we're in a chroot.

    ## Tell the kernel where to look for resuming from hibernation.
    KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE resume=LABEL=$SWAP_NAME"

    ############################################################################
    ##
    ## **Hibernation:**
    ## Disable the protective quota, create a new non-sparse zvol named "hibervol" equal to total RAM, with `refreservation=<the amount of RAM that is currently in-use>`, `volblocksize=4K`, `sync=always`, `logbias=throughput`, `primarycache=metadata`, `secondarycache=none`, `compression=off`, `com.sun:auto-snapshot=false`.
    ## * The kernel has its own compression algorithm for hibernation; ergo, ZFS compression should be disabled, lest we double-compress.
    ## * zram swap, being in RAM, is automatically included as part of the hibernation image — this means we don't need to drain it before hibernation, which is a huge win: draining a large zram swap always risks triggering an OOM killer.
    ## Format hibervol as swap with swap label "hiberswap" and set its priority to `-1` (the lowest).
    ## Run the `clean-memory` script (it drops unneeded caches and compacts memory).
    ## * Reducing the contents of RAM before hibernation makes hibernation and restore faster because less data must be written to disk.
    ## * Compacting can *slightly* help with compression ratio during hibernation (thereby speeding up I/O), and it gives the system less-fragmented RAM after resume.
    ## * Temporary impacts on performance from this cleanup isn't relevant since the system is going to go down right after, anyway.
    ## Swapon hiberswap.
    ## Run `zpool sync`, then initiate hibernation.
    ##
    ############################################################################

    #TODO

    ############################################################################
    ##
    ## **Restoration:**
    ## initramfs unlocks the pool.
    ## `systemd-hibernate-generator` handles resume.
    ## After restoration: swapoff hiberswap, then delete hibervol, then re-enable the protective quota.
    ##
    ############################################################################

    POST_NAME='post-hibernation-cleanup'
    POST_SCRIPT="/usr/local/sbin/$POST_NAME"
    cat > "$POST_SCRIPT" <<EOF && chmod +x "$POST_SCRIPT"
#!/bin/sh
set -eu
## Swapoff $SWAP_NAME
if grep -q '$SWAP_NAME' /proc/swaps; then
    SWAPOFF_BIN="$(command -v swapoff)"
    "\$SWAPOFF_BIN" -L "$SWAP_NAME"
    unset SWAPOFF_BIN
fi
## Destroy $ZVOL_NAME
HIBERVOL="$ZVOL_LOCATION"
ZFS_BIN="$(command -v zfs)"
"\$ZFS_BIN" list -H -o name "\$HIBERVOL" >/dev/null 2>&1 &&\
    exec "\$ZFS_BIN" destroy -f "\$HIBERVOL"
EOF
    POST_SERVICE="/etc/systemd/system/$POST_NAME.service"
    cat > "$POST_SERVICE" <<EOF
[Unit]
Description=Remove $ZVOL_NAME after resume
DefaultDependencies=no
Requires=zfs-import.target
After=zfs-import.target
Before=$PREP_NAME.service
ConditionPathExists=!/etc/initrd-release
[Service]
Type=oneshot
ExecStart=-$POST_SCRIPT
[Install]
WantedBy=sysinit.target
EOF
    systemctl enable "$POST_NAME" #NOTE: No `--now` because we're in a chroot.
    POST_HOOK="/etc/systemd/system-sleep/$PREP_NAME.sh"
    cat > "$POST_HOOK" <<EOF && chmod +x "$POST_HOOK"
#!/bin/sh
case "\$1/\$2" in
    post/hibernate)
        exec "$PREP_SCRIPT"
        ;;
esac
EOF

    ############################################################################
    unset PREP_NAME PREP_SCRIPT PREP_SERVICE
    unset POST_NAME POST_SCRIPT POST_SERVICE POST_HOOK
fi
