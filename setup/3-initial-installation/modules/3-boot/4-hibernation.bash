#!/usr/bin/env bash
##
## **Overview:**
## > Hibernation is a useful but universally overlooked feature in the server space.
## > In the event of a prolonged power-outage, a system connected to a UPS can hibernate instead of powering off.
## > At the end of the outage, this system can then restore to its prior state.
## > This is much faster and much-less-disruptive than a true cold boot.
## > Hibernation is also, obviously, very useful on a laptop: The system can hibernate before the battery dies, thus allowing resumption without a reboot once power is resupplied.
## > That means you no longer ever have to worry about finishing up and closing everything before your laptop dies.
##
## **Etymology:**
## > Windows, unlike Linux, properly distinguishes the roles of the on-disk memory cache ("pagefile") and hibernation cache ("hiberfile").
## > This script introduces that distinction to Linux.
## > As swap devices in a ZFS system are nigh-necessarily zvols, I have taken to calling ours a "hibervol", by analogy.
##
## **Hibernation:**
## > Trigger `sync` (to free up dirty write caches), then drop unneeded caches (`vm.drop_caches=3`), then wait 5 seconds (an arbitrary figure; heuristically set to be coincident with `vm.dirty_writeback_centisecs`).
## > Create a new sparse zvol named "hibervol", with snapshots disabled and compression enabled (using the same algorithm as zram swap: zstd-2). It should be equal to the size of zram swap + zswap + used RAM.
## > Format hibervol as swap with name "hiberswap" and priority `-1`. (the lowest possible)
## > Swapon hiberswap, then disable systemd-oomd, then swapoff zram swap, then disable zswap.
## > * If free RAM is limited, this will temporarily cause a substantial drop in performance as the kernel moves things from zram swap to hiberswap. Expect lockups and potentially thrashing if zram swap is substantial.
## > * If memory pressure is sufficiently severe, an OOM killer could be engaged. It's imperative that we avoid that eventuality. We can disable systemd's, but we can't disable the kernel's.
## > Compact memory (`vm.compact_memory=1`), then disable compression on hibervol, then `zpool sync`, then initiate hibernation.
## > * The kernel has its own compression algorithm for hibernation; ergo, ZFS compression should be disabled, lest we double-compress.
## > * Memory compaction is optional, but it may result in a higher compression ratio; and, in any case, it will help with performance after resume.
##
## **Restoration:**
## > initramfs unlocks the pool.
## > initramfs looks for the presence of hibervol.
## > If hibervol is not present, initramfs loads the system normally.
## > If hibervol is present, initramfs resumes from it.
## > If an error is encountered, the system attempts
## > After restoration: enable zswap, then swapon zram swap, then swapoff hiberswap.
## > After swapoff finishes: enable systemd-oomd, then delete hibervol.
##
## **Failsafe:**
## > We check for the existence of the hibervol on normal boots.
## > If found, we delete it and log a warning.
## > This helps ensure clean operation even in the event that something ever goes wrong with hibernation.
##
## **Contingency:**
## > Set a hard quota on the OS zpool equal to the total amount of installed RAM.
## > This naïve 1:1 reservation guarantees solvency because:
## > * zram swap is drained from zstd-2 to zstd-2 (the same algorithm).
## > * zswap is drained from lz4 to zstd-2 (a stronger algorithm).
## > * The rest of RAM is hibernated from uncompressed to kernel compression (a stronger algorithm).
## > * RAM is never at 100% use; the kernel doesn't permit it.
##
## **Whys:**
## > Why bother with this? Why not just have permanent on-disk swap all the time? Why not just not have swap at all?
## > * Swap on ZFS is a bad idea for normal operation:
## >   * System resource contention can result in *bad* scenarios where there aren't enough resources to properly steward the zvol that swap is located on at the same time as the system needs to swap/unswap in order to function.
## >   * zvol swap is not great; swapfiles are even worse.
## > * Swap partitions are extremely inelegant:
## >   * They must be encrypted or an attacker can read the full contents of your memory from your disk.
## >     * On an array, this means encrypted LUKS atop LVM OR several independent LUKS partitions; either way, you have to configure your initramfs to unlock them or you have to manually enter passwords.
## >   * They kill the beautiful dream of having ZFS be the one true master of all storage.
## >   * They prevent ZFS from running in whole-disk mode.
## >   * They significantly complicate the addition of new disks to an array.
## > * For 99.9% of a server's operation life, having on-disk swap is not only unnecessary: It's actively harmful.
## >   * The only time swap needs durability is during hibernation.
## >   * Swapping to/from compressed RAM is *ludicrously* faster than swapping to/from durable storage.
## >   * Swapping to/from durable storage competes with normal I/O, thus degrading normal I/O performance.
## >   * ZFS performance significantly degrades when there is not much freespace. A permanent capacity loss equal to total RAM can be *substantial*, and thereby pose a significant reduction to performance in a near-full pool.
## >   * Significantly reducing the space available to ZFS 99.9% of the time to simplify 0.01% of the time is a bad trade.
## > * Having no swap at all means you don't have any way to avert an OOM killer when the kernel excessively overcommits memory. Given the ease with which zram swap can be enabled, I consider it to be senseless/reckless to run swapless.
## > Why do we need two transient swap zvols?
## > * zram swap *most likely* looks like a normal swap device to the kernel, so I *assume* it is not included when hibernating. Therefore, failure to dump it beforehand *should* guarantee an unusable hibernation image.
## > * zram swap is compressed differently from how hibernated RAM is compressed, so the only way to guarantee the right amount of on-disk swap is to create one zvol per source, each matched to that source in compression expectations.
##
## **Risks:**
## > * If something goes wrong and hibernation or resume fails, you have the effects of a sudden system crash.
## > * If resume fails, you may be unable to boot without manual intervention.
## > * If memory pressure spikes too high during swap drains, an OOM killer could be triggered.
## > My goal is to eliminate these risks.

#TODO: Implement the above.
#TODO: Enable automatic hibernation when NUT detects that the UPS is low on battery.
