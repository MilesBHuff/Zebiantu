#!/bin/sh
## This file contains variables used by the other scripts in this directory.

## Names

export ENV_NAS_POOL_NAME='nas-pool'
export ENV_DAS_POOL_NAME='das-pool'

export ESP_NAME='esp'
export OS_NAME='os'
export SLOG_NAME='slog'
export SVDEV_NAME='svdev'

## Mount Options

export ESP_MOUNT_OPTIONS='noatime,lazytime,sync,flush,tz=UTC,iocharset=utf8,fmask=0137,dmask=0027,nodev,noexec,nosuid'
export OS_MOUNT_OPTIONS='noatime,lazytime,ssd,discard=async,compress=lzo'

## Misc Options

export ENV_ACCEPTABLE_DATA_LOSS_SECONDS=5 #TODO: What is optimal?

## Drive Characteristics

export ENV_HDD_SECTOR_SIZE=4096
export ENV_SSD_SECTOR_SIZE=4096

## Drive Speeds

export ENV_THEORETICAL_MAX_HDD_SPEED_MBPS=250 #TODO: Check spec sheet
export ENV_THEORETICAL_MAX_SSD_SPEED_MBPS=550 #TODO: Check spec sheet

export ENV_SLOWEST_HDD_MAX_SPEED_MBPS=250 #TODO: Measure
export ENV_SLOWEST_SSD_MAX_SPEED_MBPS=550 #TODO: Measure

export ENV_SLOWEST_HDD_AVG_SPEED_MBPS=125 #TODO: Measure
export ENV_SLOWEST_SSD_AVG_SPEED_MBPS=300 #TODO: Measure
