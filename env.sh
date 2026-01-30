#!/bin/sh
## This file contains variables used by the other scripts in this directory.

## Names

export ENV_POOL_NAME_NAS='nas-pool'
export ENV_POOL_NAME_DAS='das-pool'
export ENV_POOL_NAME_OS='os-pool'

export ENV_NAME_CACHE='cache'
export ENV_NAME_ESP='esp'
export ENV_NAME_OS='os'
export ENV_NAME_RESERVED='reserved'
export ENV_NAME_SLOG='slog'
export ENV_NAME_SVDEV='svdev'
export ENV_NAME_VDEV='vdev'

export ENV_NAME_OS_LUKS="crypt-$ENV_NAME_OS"

export ENV_SNAPSHOT_NAME_INITIAL='initial'

## Paths

export ENV_ZFS_ROOT='/media/zfs'

## Mount Options

export ENV_MOUNT_OPTIONS_ESP='noatime,lazytime,sync,flush,tz=UTC,iocharset=utf8,fmask=0137,dmask=0027,nodev,noexec,nosuid'
export ENV_MOUNT_OPTIONS_OS='noatime,lazytime,ssd,discard=async,compress=lzo' ## These options are for btrfs. This variable is currently unused.
export ENV_MOUNT_OPTIONS_ZVOL='noatime,lazytime,inode64,logbufs=8,logbsize=256k'

## Misc Options

export ENV_SECONDS_DATA_LOSS_ACCEPTABLE=5 ## You want the lowest value that doesn't significantly increase fragmentation.

## Drive Characteristics

export ENV_SECTOR_SIZE_HDD=4096
export ENV_SECTOR_SIZE_LOGICAL_HDD=4096
export ENV_SECTOR_SIZE_SSD=4096
export ENV_SECTOR_SIZE_LOGICAL_SSD=512
export ENV_SECTOR_SIZE_OS=512         ## Specifically the NAS's OS
export ENV_SECTOR_SIZE_LOGICAL_OS=512 ## Specifically the NAS's OS
export ENV_SECTOR_SIZE_AI=4096
export ENV_SECTOR_SIZE_LOGICAL_AI=4096

## Drive Speeds

export ENV_SPEED_MBPS_MAX_THEORETICAL_HDD=285 ## SeaGate Exos X20
export ENV_SPEED_MBPS_MAX_THEORETICAL_SSD=530 ## Micron 5300 Pro: 540 read, 520 write

export ENV_SPEED_MBPS_MAX_SLOWEST_HDD=243 ## Tested with `hdparm -t`: 243, 253, 270
export ENV_SPEED_MBPS_MAX_SLOWEST_SSD=430 ## Tested with `hdparm -t`: 431, 430, 430

export ENV_SPEED_MBPS_AVG_SLOWEST_HDD=$((ENV_SPEED_MBPS_MAX_SLOWEST_HDD / 2)) #TODO: Measure
export ENV_SPEED_MBPS_AVG_SLOWEST_SSD=$((ENV_SPEED_MBPS_MAX_SLOWEST_SSD / 2)) #TODO: Measure

## How many devices?
export ENV_DEVICES_IN_VDEVS=3
export ENV_DEVICES_IN_L2ARC=1

## How long, on average, until failure? (in hours)
export ENV_MTBF_NVDEV=2500000
export ENV_MTBF_SVDEV=3000000
export ENV_MTBF_L2ARC=1750000

## How long do you want these devices to last?
export ENV_MTBF_TARGET_L2ARC=2 ## In years.

## How many writes can be endured (in terrabytes per 5 years)
export ENV_ENDURANCE_NVDEV=2750
export ENV_ENDURANCE_SVDEV=2628
export ENV_ENDURANCE_L2ARC=300

## Measured speeds in MB/s (`hdparm -t` averaged across devices)
export ENV_SPEED_L2ARC=4470

## Device-specific queue depths
export ENV_NVME_QUEUE_REGIME='SATA' ## 'SATA'|'NVMe': Pick the one that best-describes your main pool's storage type.
export ENV_NVME_QUEUE_DEPTH=4096

## Sizes

export ENV_RECORDSIZE_ARCHIVE='16M' ## Most-efficient storage.
export ENV_RECORDSIZE_HDD='256K' ## Safely above the point at which all filesizes cost the same amount of time to operate on.
export ENV_RECORDSIZE_SSD='64K' ## Safely above the point at which all filesizes cost the same amount of time to operate on.

export ENV_THRESHOLD_SMALL_FILE='64K' ## This is solidly below the point at which HDD operations cost the same time no matter the filesize, so files of this size *need* to be on an SSD if at all possible for optimal performance.

export ENV_ZFS_SECTORS_RESERVED=16384 ## This is how much space ZFS gives to partition 9 on whole-disk allocations. On 4K-native disks, this unfortunately eats 64MiB instead of the standard 8MiB...

## Root ZPool Options

export ENV_ZPOOL_COMPATIBILITY='openzfs-2.2-linux' ## Highest version supported by Proxmox VE (Bookworm)

export ENV_ZPOOL_NORMALIZATION='formD' ## Most-performant option that unifies pre-composed letters and letters with combining diacritics. Downside is that it implies that all filenames are UTF-8; best to not use this setting for legacy pools, or for pools that an OS runs on.
export ENV_ZPOOL_CASESENSITIVITY='sensitive' ## Best for strictness.

export ENV_ZPOOL_ATIME='off' ## Terrible for performance, and *might* cause data duplication on snapshotting (it definitely does in btrfs). Simply put: `atime` is, fwiu, more-or-less incompatible with CoW+snapshotting.

export ENV_ZPOOL_ENCRYPTION='aes-128-gcm' ## GCM is better performance than CCM. 128 is faster than 256 and I see no evidence that it will ever be possible for classical or quantum computing to be able to realistically or affordably ever break it in my lifetime.
export ENV_ZPOOL_PBKDF2ITERS='999999' ## Run `cryptsetup benchmark` and divide PBKDF2-sha256 by 10 or less to get this number. This makes it take 125ms to unlock this pool on your current computer, and annoys the heck out of attackers.
export ENV_ZPOOL_CHECKSUM='fletcher4' ## This is the default, and is so fast as to be free. Cryptographic hashes like BLAKE3 are ridiculously slower, and provide no benefit if you are not using deduplication or `zfs send | recv`ing from untrusted devices or renting out entire datasets to users with root-level access to those datasets. `cat /proc/sys/kstat/fletcher_4_bench /proc/sys/kstat/chksum_bench` for details.

## Compression Settings

## Results of tests on ZFS 2.3.1's builtin compression algorithms
export ENV_ZPOOL_COMPRESSION_FAST='zstd-fast-1' ## 100 real copy tests reveal this algorithm to provide better performance than no compression, zle, lz4, all higher zstd-fast, and all zstd.
export ENV_ZPOOL_COMPRESSION_MOST='zstd-19' ## With ZFS 2.2's early-abort system, zstd-19 manages an average of 288MiB/s across 32 real copy tests, and it results in a stunning ratio. This is zstd's highest algorithm.

## ZSTD 1.5.7 / LZ4 9.10.0
## All speeds below are the rate at which data is written to HDDs in a real pool; though, note that the compression was not done through ZFS.
## zstd-fast-1 offers the best performance, at up to 1.73GiB/s (more than four times as fast as writing an uncompressed tar to the HDD vdev), destroying every other algorithm, and is not far off of zstd-1 in size. The other fast levels are strictly worse than even the normal levels at speed.
## lz4 offers great performance, but uses only *slightly* less CPU than zstd-fast-1 in exchange for significantly worse I/O performance and compression ratio. Imho, now obsoleted by zstd-fast-1, at least on my hardware.
## zstd-1 is very fast (up to 1GiB/s), but both it and zstd-fast-1 show wide swings in their effective performance. Their worst-cases are comparable to zstds 2-5. All values higher than zstd-1 are consistent in speed.
## zstd-2 through zstd-5 are the same performance and offer gradual decreases in size.
## zstd-6 is the last value that offers performance equal the limits of SATA III SSD speeds.
## zstd-9 is the last value before zstd-15 that offers a significant size decrease.
## zstd-10 is the last value that offers performance equal to the limits of 7200 RPM HDDs.
## zstd-16 runs at USB-2 speeds. I didn't test lower, as anything else is essentially unusably slow.
#export ENV_ZPOOL_COMPRESSION_FAST='zstd-fast-1' ## Increases effective I/O speeds more than any other algorithm. You get space savings and speed for minimal CPU.
#export ENV_ZPOOL_COMPRESSION_MOST='zstd-9' ## After going from 8-9, there are almost no additional space savings until the 15-16 jump. 16 is USB-2 speeds, so 9 wins. 9 is 343MiB/s when writing to the pool, which is amazingly good, all things considered.

## ZSTD 1.5.? / LZ4 9.?.? (from an Ubuntu Server image that I no longer have)
#export ENV_ZPOOL_COMPRESSION_FREE='lz4' ## More-accurately termed 'lz_fast'. Practically no CPU hit for huge space savings, but lackluster in I/O performance -- zstd-fast-1 more than quadruples it in I/O speed (435 vs 1720 MiB/s) and beats it in ratio too (4534297 -> 2366249 -> 1914305).
#export ENV_ZPOOL_COMPRESSION_BALANCED='zstd-4' ## Best ratio of CPU time to filesize on my system. zstd-2 also works very well -- the two are neck-and-neck, and either can win depending on chance. zstd-4 is technically slower on SSDs, but on *my* SSDs there is no difference.
#export ENV_ZPOOL_COMPRESSION_MOST='zstd-11' ## Highest level that keeps performance above HDD random I/O is 12, but on my test data it cost 6 more seconds for literally 0 gain vs 11. 11=90M/s, 12=72M/s, 13=38M/s.

## zvol settings
export ENV_ZVOL_FS='xfs' ## It seems to me like the exact features XFS lacks are the exact features zvols provide; and it also seems to me that XFS is likely to not hugely fight ZFS on things.
export ENV_ZVOL_BS='4K'  ## Avoids RMW in exchange for a higher metadata cost. Often the right trade to make for VMs, since OSes have lots of tiny files and would incur substantial RMW costs with 8K; and OSes are the only situation I'm using zvols for.
export ENV_ZVOL_FS_OPTIONS='-m reflink=0,crc=1 -i sparse=1 -l lazy-count=1' ## Disable double CoW, keep CRC just in case, make sparse just like the zvol hosting it, play nicer with TXGs.
