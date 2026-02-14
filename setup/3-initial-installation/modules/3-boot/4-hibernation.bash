#!/usr/bin/env bash
################################################################################
##
## **Blockers:**
## ZFS currently DOES NOT SUPPORT HIBERNATION, even hibernation to swap outside of ZFS.
## Do not hibernate until support exists!
##
################################################################################
##
## **Requirements:**
## You must be on a kernel that supports zram.
## You must use zram swap as your sole source of swap.
## You must be using encrypted ZFS for your operating system's root.
##
## **Overview:**
## Hibernation is a useful but universally overlooked feature in the server space.
## In the event of a prolonged power-outage, a system connected to a UPS can hibernate instead of powering off.
## At the end of the outage, this system can then restore to its prior state.
## This is much faster and much-less-disruptive than a true cold boot.
## Hibernation is also, obviously, very useful on a laptop: The system can hibernate before the battery dies, thus allowing resumption without a reboot once power is resupplied.
## That means you no longer ever have to worry about finishing up and closing everything before your laptop dies.
## That said, it is not appropriate for all situations. On systems with large amounts of RAM, writing/reading it to/from storage may be much slower than shutting down and cold-booting.
## As well, hibernation can be confusing for some applications; so it should be applied only where it makes sense and where it has been tested and confirmed to not cause problems for a particular workload.
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
##
## **Preparation:**
## Set a hard quota on the OS zpool's root dataset equal to the total amount of installed RAM (as this is the largest hibervol our algorithm will create).
## Set `resume=` on the kernel commandline.
## Enable the `resume` hook for initramfs.
##
## **Hibernation:**
## Disable the protective quota, create a new non-sparse zvol named "hibervol" equal to the size of total RAM minus free memory, with snapshots disabled, `compression=off`, `sync=always`, `volblocksize=4K`.
## * The kernel has its own compression algorithm for hibernation; ergo, ZFS compression should be disabled, lest we double-compress.
## * zram swap, being in RAM, is automatically included as part of the hibernation image — this means we don't need to drain it before hibernation, which is a huge win: draining a large zram swap always risks triggering an OOM killer.
## Format hibervol as swap with swap label "hiberswap" and set its priority to `-1` (the lowest).
## Trigger `sync` (to free up dirty write caches), then drop unneeded caches (`vm.drop_caches=3`), then wait 5 seconds (an arbitrary figure; heuristically set to be coincident with `vm.dirty_writeback_centisecs`), then compact memory (`vm.compact_memory=1`).
## * Reducing the contents of RAM before hibernation makes hibernation and restore faster because less data must be written to disk.
## * Compacting can help with compression ratio during hibernation (thereby speeding up I/O), and it gives the system less-fragmented RAM after resume.
## Swapon hiberswap.
## Run `zpool sync`, then initiate hibernation.
##
## **Restoration:**
## initramfs unlocks the pool.
## `systemd-hibernate-generator` handles resume.
## After restoration: swapoff hiberswap, then delete hibervol, then re-enable the protective quota.
##
################################################################################

## Every boot, set a new quota on the OS zpool that guarantees enough room to swap.
#TODO

## Enable resume functionality in initramfs
#TODO

## Tell the kernel where to look for resuming from hibernation.
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE resume='/dev/zvol/$ENV_POOL_NAME_OS/hibervol'"

## Add a script that runs before hibernation.
#TODO

## Add a script that runs after restore.
#TODO
