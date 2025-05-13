#!/bin/sh
## This file contains variables used by the other scripts in this directory.

## Names

export ENV_POOL_NAME_NAS='nas-pool'
export ENV_POOL_NAME_DAS='das-pool'
export ENV_POOL_NAME_OS='os-pool'

export ENV_NAME_ESP='esp'
export ENV_NAME_OS='os'
export ENV_NAME_SLOG='slog'
export ENV_NAME_SVDEV='svdev'

export ENV_NAME_OS_LUKS="crypt-$ENV_NAME_OS"

export ENV_SNAPSHOT_NAME_INITIAL='initial'

## Paths

export ENV_ZFS_ROOT='/media/zfs'

## Mount Options

export ENV_MOUNT_OPTIONS_ESP='noatime,lazytime,sync,flush,tz=UTC,iocharset=utf8,fmask=0137,dmask=0027,nodev,noexec,nosuid'
export ENV_MOUNT_OPTIONS_OS='noatime,lazytime,ssd,discard=async,compress=lzo'

## Misc Options

export ENV_SECONDS_DATA_LOSS_ACCEPTABLE=5 #TODO: What is optimal?

## Drive Characteristics

export ENV_SECTOR_SIZE_HDD=4096
export ENV_SECTOR_SIZE_SSD=4096 ## Logical: 512

## Drive Speeds

export ENV_SPEED_MBPS_MAX_THEORETICAL_HDD=285 ## SeaGate Exos X20
export ENV_SPEED_MBPS_MAX_THEORETICAL_SSD=530 ## Micron 5300 Pro: 540 read, 520 write

export ENV_SPEED_MBPS_MAX_SLOWEST_HDD=243 ## Tested with `hdparm -t`: 243, 253, 270
export ENV_SPEED_MBPS_MAX_SLOWEST_SSD=543 ## Tested with `hdparm -t`: 543, 543, 543

export ENV_SPEED_MBPS_AVG_SLOWEST_HDD=$(($ENV_SPEED_MBPS_MAX_SLOWEST_HDD / 2)) #TODO: Measure
# export ENV_SPEED_MBPS_AVG_SLOWEST_SSD=$(($ENV_SPEED_MBPS_MAX_SLOWEST_SSD / 2)) #TODO: Measure

## Sizes

export ENV_RECORDSIZE_HDD='256K'
export ENV_RECORDSIZE_SSD='64K'

export ENV_THRESHOLD_SMALL_FILE='128K' ## Theoretically I'd do 64K, but my specific data is still at less than 5% when including all files up to 128K.

## Root ZPool Options

export ENV_ZPOOL_NORMALIZATION='formD'
export ENV_ZPOOL_CASESENSITIVITY='sensitive'

export ENV_ZPOOL_ATIME='off'

export ENV_ZPOOL_ENCRYPTION='aes-256-gcm'
export ENV_ZPOOL_CHECKSUM='blake3'

export ENV_ZPOOL_COMPRESSION_FREE='lz4' ## Practically no performance implication
export ENV_ZPOOL_COMPRESSION_BALANCED='zstd-2' ## Best ratio of CPU time to filesize
export ENV_ZPOOL_COMPRESSION_MOST='zstd-9' #TODO: Benchmark different zstds, and find the highest level that doesn't decrease performance
