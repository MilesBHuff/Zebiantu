#!/bin/sh
## This file contains variables used by the other scripts in this directory.

## Names

export ENV_NAS_POOL_NAME='nas-pool'
export ENV_DAS_POOL_NAME='das-pool'
export ENV_OS_POOL_NAME='os-pool'

export ENV_ESP_NAME='esp'
export ENV_OS_NAME='os'
export ENV_SLOG_NAME='slog'
export ENV_SVDEV_NAME='svdev'

export ENV_OS_LUKS_NAME="crypt-$ENV_OS_NAME"

## Paths

export ENV_ZFS_ROOT='/media/zfs'

## Mount Options

export ENV_ESP_MOUNT_OPTIONS='noatime,lazytime,sync,flush,tz=UTC,iocharset=utf8,fmask=0137,dmask=0027,nodev,noexec,nosuid'
export ENV_OS_MOUNT_OPTIONS='noatime,lazytime,ssd,discard=async,compress=lzo'

## Misc Options

export ENV_ACCEPTABLE_DATA_LOSS_SECONDS=5 #TODO: What is optimal?

## Drive Characteristics

export ENV_HDD_SECTOR_SIZE=4096
export ENV_SSD_SECTOR_SIZE=4096 ## Logical: 512

## Drive Speeds

export ENV_THEORETICAL_MAX_HDD_SPEED_MBPS=285 ## SeaGate Exos X20
export ENV_THEORETICAL_MAX_SSD_SPEED_MBPS=530 ## Micron 5300 Pro: 540 read, 520 write

export ENV_SLOWEST_HDD_MAX_SPEED_MBPS=243 ## Tested with `hdparm -t`: 243, 253, 270
export ENV_SLOWEST_SSD_MAX_SPEED_MBPS=543 ## Tested with `hdparm -t`: 543, 543, 543

export ENV_SLOWEST_HDD_AVG_SPEED_MBPS=$(($ENV_SLOWEST_HDD_MAX_SPEED_MBPS / 2)) #TODO: Measure
export ENV_SLOWEST_SSD_AVG_SPEED_MBPS=$(($ENV_SLOWEST_SSD_MAX_SPEED_MBPS / 2)) #TODO: Measure

export ENV_LARGE_FILE_THRESHOLD='256K'
export ENV_SMALL_FILE_THRESHOLD='128K' ## Theoretically I'd do 64K, but my specific data is still at less than 5% when including all files up to 128K.
