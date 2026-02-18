#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.
################################################################################

## We should disable default resume functionality, since it flat-out will not work with ZFS; we have to use the custom design specified below.
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE noresume rd.noresume"
## If initramfs-tools is installed, we should also disable its version of resume.
if dpkg -l | grep -q 'initramfs-tools'; then
    cat > '/etc/initramfs-tools/conf.d/disable-resume' <<'EOF'
RESUME=none
EOF
## As this is run from a LiveCD, we know that if `initramfs-tools` is installed, it's because the system shipped with it, which means `dracut` is not being used for initramfs generation.
## In this scenario, we shouldn't present the user with the option to enable hibernation/resume, since the below depends on dracut and I don't think there's a robust way to make resuming safe without dracut/systemd.
## Newer versions of Ubuntu (25.10+) ship with dracut as their default initramfs generator, and so should be able to handle the below.
else

    ## **Blockers:**
    echo 'ZFS currently does not officially support hibernation, even hibernation to swap outside of ZFS.' >&2
    echo -e 'It is safe to latently enable hibernation in your configurations, but actually hibernating is \e[1munsupported\e[0m.' >&2
    echo -e 'Hibernation vis-à-vis this script will not work until Debian and Ubuntu use Dracut.' >&2
    echo -e 'As well: the hibernation that this script enables is, at present, \e[1mcompletely untested\e[0m.' >&2
    echo -e '\e[1mProceed at your own risk!\e[0m' >&2
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
        SWAP_LABEL="hiberswap"
        ZVOL_NAME="hibervol"
        ZVOL_PATH_IN_ZPOOL="$ENV_POOL_NAME_OS/$ZVOL_NAME"
        ZVOL_PATH_IN_DEV="/dev/zvol/$ZVOL_PATH_IN_ZPOOL"

        #############################
        ##   G R O U N D W O R K   ##
        #############################

        ## Tell the kernel where to look for resuming from hibernation.
        KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE resume=$ZVOL_PATH_IN_DEV"

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
        cat > "$PREP_SERVICE" <<EOF && systemctl enable "$PREP_NAME" #NOTE: No `--now` because we're in a chroot.
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

        ###########################################
        ##   A F T E R   R E S T O R A T I O N   ##
        ###########################################

        ## Swap off hiberswap and delete hibervol
        POST_NAME='post-hibernation-cleanup'
        POST_SCRIPT="/usr/local/sbin/$POST_NAME"
        cat > "$POST_SCRIPT" <<EOF && chmod +x "$POST_SCRIPT"
#!/bin/sh
set -eu
if [ -b "$ZVOL_PATH_IN_DEV" ]; then

    ## Swapoff $SWAP_LABEL
    if grep -q "$ZVOL_NAME" /proc/swaps; then
        SWAPOFF_BIN="$(command -v swapoff)"
        "\$SWAPOFF_BIN" -L "$SWAP_LABEL"
        unset SWAPOFF_BIN
    fi

    ## Destroy $ZVOL_NAME
    HIBERVOL="$ZVOL_PATH_IN_ZPOOL"
    ZFS_BIN="$(command -v zfs)"
    "\$ZFS_BIN" list -H -o name "\$HIBERVOL" >/dev/null 2>&1 &&\
        exec "\$ZFS_BIN" destroy -f "\$HIBERVOL"
fi
exit 0
EOF
        POST_SERVICE="/etc/systemd/system/$POST_NAME.service"
        cat > "$POST_SERVICE" <<EOF && systemctl enable "$POST_NAME"
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

        ## Re-enable protective quota
        POST_HOOK="/etc/systemd/system-sleep/00-$PREP_NAME.sh"
        cat > "$POST_HOOK" <<EOF && chmod +x "$POST_HOOK"
#!/bin/sh
case "\$1/\$2" in
    post/hibernate)
        exec "$PREP_SCRIPT"
        ;;
esac
EOF

        ################################
        ##   H I B E R N A T I O N   ###
        ################################
        ## Create a script that runs before each hibernation:
        ## * Disable the protective quota
        ## * Create a new non-sparse zvol named "hibervol" equal to total RAM, with `refreservation=<total RAM>`, `volblocksize=4K`, `sync=always`, `logbias=throughput`, `primarycache=metadata`, `secondarycache=none`, `compression=off`, `com.sun:auto-snapshot=false`.
        ##   * The kernel has its own compression algorithm for hibernation; ergo, ZFS compression should be disabled, lest we double-compress.
        ##   * zram swap, being in RAM, is automatically included as part of the hibernation image — this means we don't need to drain it before hibernation, which is a huge win: draining a large zram swap always risks triggering an OOM killer.
        ## * Format hibervol as swap with swap label "hiberswap" and set its priority to `-1` (the lowest).
        ## * Swapon hiberswap.
        ## * Stop any ongoing scrubs/resilvers, out of an abundance of caution.
        ## * Run the `clean-memory` script (it drops unneeded caches and compacts memory).
        ##   * Reducing the contents of RAM before hibernation makes hibernation and restore faster because less data must be written to disk.
        ##   * Compacting may *slightly* help with compression ratio during hibernation (thereby speeding up I/O), and it gives the system less-fragmented RAM after resume.
        ##   * Temporary impacts on performance from this cleanup aren't relevant since the system is going to go down right after, anyway.
        ## * Run `zpool sync`.
        ## * Allow hibernation to happen.
        ################################
        MAIN_NAME='zfs-hibernate'

        ## This is the script that implements the above.
        MAIN_SCRIPT="/usr/local/sbin/$MAIN_NAME"
        cat > "$MAIN_SCRIPT" <<EOF && chmod +x "$MAIN_SCRIPT"
#!/bin/sh
set -eu

CLEAN_MEMORY_BIN='/usr/local/sbin/clean-memory'
MKSWAP_BIN="$(command -v mkswap)"
SWAPON_BIN="$(command -v swapon)"
SYSTEMCTL_BIN="$(command -v systemctl)"
ZFS_BIN="$(command -v zfs)"
ZPOOL_BIN="$(command -v zpool)"

SWAP_LABEL="$SWAP_LABEL"
ZVOL_PATH_IN_ZPOOL="$ZVOL_PATH_IN_ZPOOL"
ZVOL_PATH_IN_DEV="$ZVOL_PATH_IN_DEV"
ZPOOL_DATASET="$ENV_POOL_NAME_OS"

## Get total RAM
TOTAL_RAM="\$(awk '/^MemTotal:/ {print \$2}' /proc/meminfo)"
if [ -z "\$TOTAL_RAM" ]; then
    echo "\$0: Unable to determine total RAM." >&2
    exit 1
fi
TOTAL_RAM=\$((TOTAL_RAM * 1024))

## Remove protective quota
"\$ZFS_BIN" set 'quota=off' "\$ZPOOL_DATASET"
unset ZPOOL_DATASET
#NOTE: The quota effectively guarantees we have enough storage to fit TOTAL_RAM onto disk even without compression.

## Create zvol
"\$ZFS_BIN" create \
    -V "\$TOTAL_RAM" \
    -o refreservation="\$TOTAL_RAM" \
    -b 4K \
    -o sync=always \
    -o logbias=throughput \
    -o primarycache=metadata \
    -o secondarycache=none \
    -o compression=off \
    -o com.sun:auto-snapshot=false \
    "\$ZVOL_PATH_IN_ZPOOL"
unset ZFS_BIN ZVOL_PATH_IN_ZPOOL TOTAL_RAM

## Swapify
"\$MKSWAP_BIN" -L "\$SWAP_LABEL" "\$ZVOL_PATH_IN_DEV"
unset MKSWAP_BIN
"\$SWAPON_BIN" -p '-1' "\$ZVOL_PATH_IN_DEV"
unset SWAPON_BIN ZVOL_PATH_IN_DEV

## Stop scrubs/resilvers
"\$ZPOOL_BIN" scrub -s "\$ENV_POOL_NAME_OS" >/dev/null 2>&1 || true

## Sync I/O and drop unneeded pages
[ -x "\$CLEAN_MEMORY_BIN" ] && "\$CLEAN_MEMORY_BIN" || true #NOTE: This runs \`sync\` before dropping unneeded caches. This affects only native Linux I/O — *not* ZFS I/O.
unset CLEAN_MEMORY_BIN
"\$ZPOOL_BIN" sync
unset ZPOOL_BIN

## Initiate hibernation.
exit 0
EOF

        ## This fires the above script off right before every systemd-mediated hibernation.
        MAIN_HOOK="/etc/systemd/system-sleep/99-$MAIN_NAME.sh"
        cat > "$MAIN_HOOK" <<EOF && chmod +x "$MAIN_HOOK"
#!/bin/sh
case "\$1/\$2" in
    pre/hibernate)
        exec "$MAIN_SCRIPT"
        ;;
esac
EOF
        echo -e '\e[1mAlways\e[0m hibernate with `systemctl hibernate`; do not \e[1mever\e[0m hibernate in any other way or you \e[1mwill\e[0m risk corruption. \e[1mYou have been warned!\e[0m' >&2

        #####################
        ##   R E S U M E   ##
        #####################
        ## * Modify the initramfs boot sequence so that the following happen in sequence:
        ##   * The stock `resume` functionality does not run. (Already ensured early-on in this script.)
        ##   * Unlock the root pool as per normal.
        ##   * Run a custom `resume-start` script:
        ##     * Get the root pool, as passed via kernel commandline by ZFSBootMenu
        ##     * Import root pool read-only without mounting anything.
        ##     * Ensure the kernel is aware of device changes.
        ##   * `systemd-hibernate-resume` handles the kernel's `resume=` parameter and attempts to resume.
        ##   * If resuming fails or doesn't happen, run a custom `resume-end` script:
        ##     * Get the root pool, as passed via kernel commandline by ZFSBootMenu
        ##     * Export root pool.
        ##   * The system continues booting as per normal.
        ## * During boot and after resume, custom scripts defined earlier in this installer script will detect and remove any remnant hibernation swap or zvol.
        #####################

        ## Prepare the initramfs to resume from hibernation
        RESUME_START_NAME='resume-start'
        RESUME_START_SCRIPT="/usr/local/sbin/.$RESUME_START_NAME"
        cat > "$RESUME_START_SCRIPT" <<EOF && chmod +x "$RESUME_START_SCRIPT"
#!/bin/sh
set -eu
ROOT_SPEC="\$(sed -n 's/.*root=ZFS=\([^ ]*\).*/\1/p' /proc/cmdline)" #AI
ZPOOL="\${ROOT_SPEC%%/*}"
if zpool list "\$ZPOOL" >/dev/null 2>&1; then
    ## The pool shouldn't be imported. Fwiu, ZFSBootMenu imports it read-only, and then that import disappears during kexec.
    ## If the pool *is* imported for some reason, it *should* be fine to continue if it's imported read-only.
    ## If it's not read-only, we need to fail out — resume is probably dead in the water.
    if [ \$(zpool get -Ho value readonly "\$ZPOOL") = 'off' ]; then
        echo "\$0: '\$ZPOOL' pre-imported read/write; resume is compromised. Bailing out..." >&2
        exit 1
    fi
else
    zpool import -No readonly=on -o cachefile=none "\$ZPOOL"
fi
udevadm settle
EOF
        RESUME_START_SERVICE="/etc/systemd/system/$RESUME_START_NAME.service"
        cat > "$RESUME_START_SERVICE" <<EOF && systemctl enable "$RESUME_START_NAME"
[Unit]
Description=Permit systemd to resume from the root zpool
ConditionPathExists=/etc/initrd-release
DefaultDependencies=no
Before=systemd-hibernate-resume.service zfs-import.target zfs-import-cache.service zfs-import-scan.service zfs-mount.service initrd-root-fs.target
After=zfs-load-key.service systemd-udevd.service
[Service]
Type=oneshot
ExecStart=-$RESUME_START_SCRIPT
[Install]
WantedBy=initrd.target
EOF

        ## Prepare the initramfs for a normal boot after attempting resume
        RESUME_END_NAME='resume-end'
        RESUME_END_SCRIPT="/usr/local/sbin/.$RESUME_END_NAME"
        cat > "$RESUME_END_SCRIPT" <<EOF && chmod +x "$RESUME_END_SCRIPT"
#!/bin/sh
set -eu
ROOT_SPEC="\$(sed -n 's/.*root=ZFS=\([^ ]*\).*/\1/p' /proc/cmdline)" #AI
ZPOOL="\${ROOT_SPEC%%/*}"
if zpool list "\$ZPOOL" >/dev/null 2>&1; then
    zpool export "\$ZPOOL" || true
fi
EOF
        RESUME_END_SERVICE="/etc/systemd/system/$RESUME_END_NAME.service"
        cat > "$RESUME_END_SERVICE" <<EOF && systemctl enable "$RESUME_END_NAME"
[Unit]
Description=Permit systemd to boot after attempting to resume
ConditionPathExists=/etc/initrd-release
DefaultDependencies=no
After=$RESUME_START_NAME.service systemd-hibernate-resume.service
Before=initrd-root-fs.target zfs-import.target zfs-import-cache.service zfs-import-scan.service zfs-mount.service
[Service]
Type=oneshot
ExecStart=-$RESUME_END_SCRIPT
[Install]
WantedBy=initrd.target
EOF

        #######################
        ##   C L E A N U P   ##
        #######################
        unset PREP_NAME PREP_SCRIPT PREP_SERVICE
        unset POST_NAME POST_SCRIPT POST_SERVICE POST_HOOK
        unset MAIN_NAME MAIN_SCRIPT              MAIN_HOOK
        unset SWAP_LABEL ZVOL_NAME ZVOL_PATH_IN_ZPOOL ZVOL_PATH_IN_DEV
        unset RESUME_START_NAME RESUME_START_SCRIPT RESUME_START_SERVICE
        unset RESUME_END_NAME   RESUME_END_SCRIPT   RESUME_END_SERVICE
    fi
fi
