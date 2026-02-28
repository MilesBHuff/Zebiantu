#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.

## Configure swap
echo ':: Configuring swap...'
## (Note: I refer to the benchmarks [here](https://github.com/inikep/lzbench/blob/271066457e5f89c78ef186987b03c0ad73404b32/README.md#benchmarks) below as a ballpark. In practice, every machine differs. They for instance quite underestimate my NAS: [the EPYC 9554 is 30.9% slower at single-threading than the 4464P](https://www.cpubenchmark.net/compare/5304vs6073/AMD-EPYC-9554-vs-AMD-EPYC-4464P).)
##
## Putting live swap on ZFS is *very* fraught; don't do it!
## Using a swap partition is a permanent loss of disk space, and there is much complexity involved because it must be encrypted — that means mdadm and LUKS beneath it.
## Swapping to zram (a compressed RAMdisk) is by *far* the simplest solution *and* its size is dynamic according to need, but it cannot be hibernated to.
## Hibernation support can be re-added by creating a temporary swap zvol when hibernation is requested, and removing it after resuming. (This is implemented in `boot/hibernation.bash`.)
## (In principle, because this swap zvol's size is dynamically allocated according to current memory usage, this actually gives a stronger guarantee of being able to hibernate than many fixed-size swap partitions.)
##
## Because RAM is not plentiful, we want to compress swap so that we can store as much as possible; but high compression has a non-negligible cost when swapping in and out frequently.
## zswap is an optional intermediate cache between RAM and the actual swap device, with its own compression settings.
## When enabled, zswap contains things which were recently swapped-out, and so are most-likely to be swapped back in; while the actual swap then holds stuff that has been cold for a while.
## This situation allows us to use heavier compression for the zram for maximum swap size, without risking a corresponding performance hit during swap thrashing.
## When data is flushed from zswap to the real swap device, it is first decompressed. While this does mean that each hop now needs decompression *and* compression, decompression is an order of magnitude faster; so in practice, latency is overwhelmingly dominated by compression, and decompression costs can largely be ignored.
## For zswap, then, we want to use the lightest reasonable compression algorithm: lz4, which compresses to 47.60% at 577MB/s in lzbench's sample results.
##
## In my tests, a well-sized (17%) zswap prevented all churn at the zram swap level. This means that zram swap can have a relatively high compression level.
## However, in situations of near-total RAM+swap use, I am not convinced that the zram swap will *never* see churn. So it still needs to be fast-enough to handle reclaim storms at a reasonable rate.
## For this, I feel the following is probably the best value: zstd-1, which compresses to 34.64% at 422MB/s in lzbench's sample results.
##
## We can go further, though. On any system with swap, there will always be some very cold pages that almost never need to be accessed. We can afford to compress these heavily.
## On modern kernels (5.19+), zram swap allows you to configure any block device as a writeback target for it. There is nothing saying we can't use a second normal (non-swap) zram device as this target.
## This gives us a third and final tier in our RAM compression hierarchy: zstd-5, which compresses to 29.74% at 125MB/s in lzbench's sample results.
## Note: In Linux 7.0+, zram swap no longer decompresses before writeback; in versions prior, it does. This means the decompression cost is skipped entirely outside of the initial zswap -> zram swap step.
## Also note: Writeback is not on a true LRU basis like zswap and swap are. It's still important therefore to catch churn *before* the zram swap layer... which we are doing via zswap.
##
## But we can go further, still! We can give our zram writeback device its own writeback device... in the form of a zvol.
## Almost none of the usual concerns around swapping to a zvol apply in this scenario. So if it helps avoid an OOM killer, it's worth doing.
## The compression level on this zvol can be even higher than zstd-5, since every increase in compression reduces how much data must be physically written, thereby speeding up I/O.
## In my own compression tests to my actual pool, even zstd-19 was still 288MB/s *in terms of how much equivalent uncompressed data was being written*. Now, granted, I have a CPU with 50% better single-thread performance than the lzbench benchmark, but that's in spite of ZFS's compression algorithms being older and slower than the ones in lzbench!
## So unless your CPU is weak, I would lean toward maxing the compression ratio on this zvol, since it gives you seriously more virtual memory without tanking performance.
##
## The next question is one of sizing.
## We need to leave enough free RAM to where the system does not experience severe memory pressure (which tends to happen around *roughly* 80% utilization).
## 75% is the absolute highest I would think that we can realistically go for zswap + zram swap + zram writeback, since going any higher forces the system into constant inescapable severe memory pressure and starts risking the OOM killer.
## Unfortunately, with ZFS, going for 75% is untenable: the ARC *will not swap* and is already compressed. So whatever percents we choose to go with *must* allow ARC *plus* live system memory to fit in uncompressed RAM.
## That may seem to beg the question of "Do we also need to cap ARC?", but I don't think we do: it will already dynamically shrink to avoid pressuring the system. So as our compressed memory tiers grow, ARC will shrink to accomodate them. Leaving ARC uncapped allows ARC to take advantage of when your RAM+swap usage is low, which may be all or most of the time.
## I know from experience that 17% (1/6 of RAM) for zswap works very well at catching churn. I suspect that 17% is likely to also be a good value to use for the very cold pages.
## That leaves 17% or 33% for the main-stage zram swap, depending on how much room must remain for system + ARC (50% or 33%).
## As I am perennially short on RAM and ARC is not essential for performance with my storage topologies, I am opting for a zram swap of 33%, thus bringing my total compressed RAM to 67% of total system memory, leaving only 11GB for ARC + system on my NAS.
## We probably don't want the zvol writeback device to be huge, since it is functionally a permanent reduction in usable disk space, and since going too large would encourage using so much RAM that the supposed-to-be-cold tiers start to become warm.
## I suggest therefore that 12.5% of RAM be allocated to the zvol device — a nice, round number guaranteed to be so small as to be negligible in disk-space cost yet still tremendous in value as virtual memory expansion.
##
## What this comes out to, is that a system with 32GB of physical memory has effectively ***roughly*** 96GB of useable memory... which is kinda bonkers, and very welcome in a world where RAM is scarce and expensive.
##
## Note that this can significantly increase the damage done by bit-flips in systems without ECC, since each single flip can now corrupt an entire compressed page of memory in one go.
## (Bit-fips are a real concern: on systems with 128GB of RAM, 1–2 bit-flips per day is actually *expected*.)
## The flip-side, however, is that zram actually *improves* memory safety *overall*, because zstd is checksummed. (Normally, non-ECC memory has almost no way to know if there was corruption.)
##
## For devices weak on CPU, I would suggest *not* using the in-RAM writeback tier, increasing zram swap to cover that allocation, and configuring the on-disk writeback tier to have the same compression level as the zram swap or if Linux 7.0+ to have no compression.
##
## I have used a more-conservative version of this profile (17% zswap, 33% zram swap, no writeback device) in two systems that operate under intense memory pressure:
## * a laptop from 2012 being asked to run modern Firefox all day long
## * a very-memory-constrained Minecraft VPS.
## Interactive performance on the laptop improved so noticeably I didn't even bother testing it formally except to verify that, yes, zswap will happily cache a zram swap.
## On the Minecraft server:
## * `vmstat 1` indicated no thrashing even when stressing it with the hardest workloads I could give it.
## * `watch -n1 cat /proc/pressure/memory` indicated no significant memory pressure even under the worst workloads
## * `free -h` has significant free memory and page cache
## All in spite of the fact that that server has so little RAM that it physically cannot run without hundreds of MiB of swap usage.
##
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE zswap.enabled=1 zswap.max_pool_percent=17 zswap.compressor=lz4 zswap.zpool=zsmalloc zswap.same_filled_pages_enabled=1" #NOTE: Fractional percents (eg, `12.5`) are not possible.
## This uses the same settings used in `boot/hibernation.bash`; look there for explanations on why they were chosen.
declare -i WRITEBACK_GiB=$(awk '/MemTotal/ {print int((int($2/1024/1024+0.5)/8)+0.5)}' '/proc/meminfo') ## Sets to 1/8 of total system memory, rounded to the nearest whole GiBs.
zfs create \
    -V ${WRITEBACK_GiB}G \
    -o refreservation=${WRITEBACK_GiB}G \
    -b 4K \
    -o sync=disabled \
    -o primarycache=metadata \
    -o secondarycache=none \
    -o compression=zstd-19 \
    -o com.sun:auto-snapshot=false \
    "$ENV_POOL_NAME_OS/zram-writeback"
apt install -y systemd-zram-generator
## Yes, I know that `zram-fraction` is redundant when using `zram-size`; I'm just setting it and `max-zram-size` (which must be disabled else `zram-size` is ignored) to cleanly override the defaults for `[zram0]`.
cat > '/etc/systemd/zram-generator.conf.d/zram0.conf' <<EOF
[zram0]
fs-type = swap
swap-priority = 32767
compression-algorithm = zstd(level=1)
max-zram-size = none
zram-fraction = 0.3333333333333333
zram-size = ram / 3
writeback-device = /dev/zram1
EOF
cat > '/etc/systemd/zram-generator.conf.d/zram1.conf' <<EOF
[zram1]
fs-type = none
compression-algorithm = zstd(level=5)
max-zram-size = none
zram-fraction = 0.1666666666666667
zram-size = ram / 6
writeback-device = /dev/zvol/$ENV_POOL_NAME_OS/zram-writeback
EOF
## These overrides ensure that each writeback device is ready before we start its zram swap device.
cat > '/etc/systemd/system/systemd-zram-setup@zram0.service.d/override.conf' <<EOF
[Unit]
Requires=systemd-zram-setup@zram1.service
After=systemd-zram-setup@zram1.service
ConditionPathExists=/dev/zram1
EOF
cat > '/etc/systemd/system/systemd-zram-setup@zram1.service.d/override.conf' <<EOF
[Unit]
Requires=zfs.target zfs-import.target
After=zfs.target zfs-import.target
RequiresMountsFor=/dev/zvol
ConditionPathExists=/dev/zvol/$ENV_POOL_NAME_OS/zram-writeback
EOF
## These are explanations of why you should not use zram for `/tmp` and `/run`.
cat > '/etc/systemd/zram-generator.conf.d/tmp.conf' <<'EOF'
## /tmp
## * Vanilla tmpfs can swap (especially if it doesn't have a limit), so its stale files are *already* compressed via zswap + zram swap.
## * Compression DRAMATICALLY slows RAM.
## Given the above two considerations, `/tmp` on zram is quite unwise.
EOF
cat > '/etc/systemd/zram-generator.conf.d/run.conf' <<'EOF'
## /run
## This is mounted as tmpfs extremely early, before generators run; consequently, it is not possible to use zram for it (at least not in *this* way).
## Also: You don't *want* to *anyway*, because compression DRAMATICALLY slows RAM.
EOF
## This is a sample zram device. (Useful if you need to declare one later.)
cat > '/etc/systemd/zram-generator.conf.d/zram2.conf' <<'EOF'
## Example general-purpose zram device
# [zram2]
# zram-size = 1G
# compression-algorithm = lz4
# fs-type = ext4
## Enable `metadata_csum` if you don’t trust your RAM.
# fs-create-options = "-E lazy_itable_init=0,lazy_journal_init=0 -m0 -O none,extent,dir_index,extra_isize=256 -T small"
## No point in `lazytime` when the filesystem is in RAM.
# options = noatime,discard
## Yes, this should generate and mount before anything needs it.
# mount-point = /foo
EOF
# systemctl daemon-reload ## Shouldn't run from chroot.
# systemctl start systemd-zram-setup@zram0 ## Shouldn't start/stop from chroot.

## Tune sysctl to reflect that swap is now in RAM.
idempotent_append 'vm.page-cluster=0' '/etc/sysctl.d/62-io-tweakable.conf' ## With the high speed of RAM and the CPU cost of zstd compression, readahead actually slows I/O. (https://www.reddit.com/r/Fedora/comments/mzun99/new_zram_tuning_benchmarks)
##
## When your main filesystem is ZFS, swappiness is less-important than normal, since ZFS maintains its own cache for most data: the ARC.
## That said, Linux's page cache is still used for:
## * `mmap`ped files (ELF binaries, shared libs, etc).
## * tmpfs and other kernel-managed shared memory.
## * Non-ZFS filesystems (ESP, external storage, etc).
## So there is still value in tuning swappiness.
##
## Because zram swap means that swap is in memory, the kernel's usual assumption that swap is slow has been made false. We need to let the kernel know.
## Swappiness encodes a ratio in an integer from 0–200. Lower numbers mean that swap is slower than storage, while higher numbers mean the opposite.
## On systems composed of just one class of device, you can actually calculate the ideal value for your setup by looking at the ratio of random 4K IOPS in your swap versus in your storage.
##
## However, a zpool is not one device, but a tier of them (ARC>L2ARC>svdev/vdev); and the device that contributes most to I/O varies by workload; so there is no single IOPS figure that can be calculated for the entire pool.
## Also, cache misses behave roughly like a harmonic mean (or so says AI), because even a tiny fraction of HDD hits can utterly wreck the IOPS figure.
## One might therefore suppose that swappiness ought to be set to match HDDs no matter the speeds of the other tiers, since the HDDs' impacts on IOPS are so outsized.
##
## Raw figures, however, can be misleading. On a well-architected pool, most random I/O is metadata and small files (which are on SSDs); this significantly cuts down on random I/O on HDDs, biasing them towards sequential I/O (which is much faster).
## As well, it seems like the vast majority of Linux's page cache is going to be dominated by the OS pool, which should always be 100% SSDs.
## Summarily: the impacts of HDD hits may not be as high as contextless figures suggest, and the Linux page cache may not actually have anything from those HDDs.
## Accordingly, the prior supposition that the swappiness of a zpool should be tuned solely per HDDs could well be false.
##
## Ultimately, tuning swappiness without testing it is an art, not a science — I cannot theorize this value into some kind of perfection.
## But I *can* aim to make a ballpark default that works well-enough for zram swap across a myriad of systems.
## SATA SSDs have performance characteristics intermediate between those of HDDs and those of NVMes.
## In a mirror, such as is common for zpools, the effective average concurrency you may suspect should be intermediate between the extremes of 1 drive and all the drives. For a two-way mirror, that's 1.5.
## Per AI, a figure representative of a typical enterprise-grade SATA SSD for 4K random reads per second is 96K. If we scale that by 1.5 to represent a mirror, we get 144K.
## Also per AI, a figure representative of a zram swap with zstd compression on a typical computer with DDR4-ECC could be around 700K, based on some online benchmarks; but the exact number varies wildly by hardware and compression level.
## If we ratio those two, we get an optimal swappiness of 166. Sanity check: that's in-line with other recommendations. Pop!_OS ships with 180, and a kernel.org example used 133.
##
## It is important to note that this value is just meant as a general-purpose "probably okay" figure. Your specific hardware (CPU, RAM, storage devices, storage topology) can have wildly different optimums.
## The algorithm to use is: `200 * ((s / d) / (1 + (s / d)))` (where `s` is "swap IOPS" and `d` is "disk IOPS")
## You should benchmark 4K random reads per second on your OS pool and on a zram device, using `fio`; then plug those figures into the above formula and use it for your swappiness value.
idempotent_append 'vm.swappiness=166' '/etc/sysctl.d/62-io-tweakable.conf'
## See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/61-io-static.conf
## The gist is: these tell the kernel to ensure a larger cushion of free space. The defaults are tuned to avoid swapping to disk; those default assumptions are inverted by a régime of compressed in-RAM swap.
idempotent_append 'vm.watermark_scale_factor=125'  '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.watermark_boost_factor=2500' '/etc/sysctl.d/961-io-static.conf'

## Configure `/tmp` as tmpfs
echo ':: Configuring `/tmp`...'
cp /usr/share/systemd/tmp.mount /etc/systemd/system/
mkdir -p /etc/systemd/system/tmp.mount.d
cat > /etc/systemd/system/tmp.mount.d/override.conf <<'EOF'
[Mount]
Options=mode=1777,nosuid,nodev,size=5G,noatime
## 5G is enough space to have 1G free while extracting a 4G archive (the max supported by FAT32). 1G is plenty for normal operation. ## No point in `lazytime` when the filesystem is in RAM.
[Install]
WantedBy=local-fs.target
EOF
# systemctl daemon-reload ## Normally required for the below `enable` to work, but `daemon-reload` shouldn't be run from `chroot`. We may actually be fine to skip in our specific situation, since we *have* configured systemd to run in offline mode for this chroot.
sudo systemctl enable tmp.mount
mkdir -p /etc/systemd/system/console-setup.service.d
cat > /etc/systemd/system/console-setup.service.d/override.conf <<'EOF' #BUG: Resolves an upstream issue where console-setup can happen shortly before tmpfs mounts and accordingly fail when tmpfs effectively deletes /tmp while console-setup is happening.
[Unit]
After=tmp.mount
EOF

## Enable sophisticated OOM-killing before the kernel's last-resort OOM-killing.
echo ':: Configuring OOM behavior...'
apt install -y systemd-oomd
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE psi=1"
systemctl enable systemd-oomd
## See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/68-debug.conf
idempotent_append 'vm.oom_dump_tasks=0'           '/etc/sysctl.d/968-debug.conf'
## See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/61-io-static.conf
idempotent_append 'vm.oom_kill_allocating_task=0' '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.overcommit_memory=0'        '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.overcommit_ratio=80'        '/etc/sysctl.d/961-io-static.conf'
