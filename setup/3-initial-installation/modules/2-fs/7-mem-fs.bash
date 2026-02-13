#!/usr/bin/env bash

## Configure swap
echo ':: Configuring swap...'
## Putting live swap on ZFS is *very* fraught; don't do it!
## Using a swap partition is a permanent loss of disk space, and there is much complexity involved because it must be encrypted — that means mdadm and LUKS beneath it.
## Swapping to zram (a compressed RAMdisk) is by *far* the simplest solution *and* its size is dynamic according to need, but it cannot be hibernated to.
## Hibernation support can be re-added by creating a temporary swap zvol when hibernation is requested, and removing it after resuming.
## (In principle, because this swap zvol's size is dynamically allocated according to current memory usage, this actually gives a stronger guarantee of being able to hibernate than many fixed-size swap partitions.)
## Because RAM is not plentiful, we want to compress swap so that we can store as much as possible; but high compression has a non-negligible cost when swapping in and out frequently.
## zswap is an optional intermediate cache between RAM and the actual swap device, with its own compression settings.
## When enabled, zswap contains things which were recently swapped-out, and so are most-likely to be swapped back in; while the zram then holds stuff that has been cold for a long time.
## This situation allows us to use heavier compression for the zram for maximum swap size, without risking a corresponding performance hit during swap thrashing.
## For zswap, then, we want to use the lightest reasonable compression algorithm.
## The main downside is that, when things move from zswap to the zram, they must first be decompressed before being recompressed. That's not a big deal, though, since only particularly cold pages should ever make it to the zram.
## We need to leave enough free RAM to where the system does not experience memory pressure (which becomes a serious problem around *roughly* 80% utilization).
## 50% is about the highest reasonable for zswap + zram, since that allows 30% for normal system use when factoring that the last 20% are pressured. (Of course, the exact percents that make sense do depend somewhat on absolute system memory and idle workload.)
## With 50% dedication, a 1:2 ratio of zswap:zram keeps us close to the default values for each. That's 16.67% for zswap, and 33.33% for the zram.
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE zswap.enabled=1 zswap.max_pool_percent=17 zswap.compressor=lz4" #NOTE: Fractional percents (eg, `12.5`) are not possible.
apt install -y systemd-zram-generator
cat > /etc/systemd/zram-generator.conf <<'EOF'
## zram swap
[zram0]
zram-size = ram / 3
#TODO: Tune compression level.
compression-algorithm = zstd(level=2)
## Priority should be maxed, to help avoid slower devices becoming preferred.
swap-priority = 32767

## /tmp
## * Vanilla tmpfs can swap (especially if it doesn't have a limit), so its stale files are *already* compressed via zswap + zram swap.
## * Compression DRAMATICALLY slows RAM.
## Given the above two considerations, `/tmp` on zram is quite unwise.

## /run
## This is mounted as tmpfs extremely early, before generators run; consequently, it is not possible to use zram for it (at least not in *this* way).

## Example general-purpose zram device
# [zram1]
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

## Configure `/tmp` as tmpfs
echo ':: Configuring `/tmp`...'
cp /usr/share/systemd/tmp.mount /etc/systemd/system/
systemctl enable tmp.mount
mkdir -p /etc/systemd/system/tmp.mount.d
cat > /etc/systemd/system/tmp.mount.d/override.conf <<'EOF'
[Mount]
Options=mode=1777,nosuid,nodev,size=5G,noatime
## 5G is enough space to have 1G free while extracting a 4G archive (the max supported by FAT32). 1G is plenty for normal operation. ## No point in `lazytime` when the filesystem is in RAM.
EOF
mkdir -p /etc/systemd/system/console-setup.service.d
cat > /etc/systemd/system/console-setup.service.d/override.conf <<'EOF' #BUG: Resolves an upstream issue where console-setup can happen shortly before tmpfs mounts and accordingly fail when tmpfs effectively deletes /tmp while console-setup is happening.
[Unit]
# Requires=tmp.mount
After=tmp.mount
EOF
# systemctl daemon-reload ## Shouldn't run from chroot.
