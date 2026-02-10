#!/bin/sh
## This file contains variables used by various scripts related to system setup.

## Envfiles
export ENV_SETUP_ENVFILE='/env/setup-env.sh'
export ENV_FILESYSTEM_ENVFILE='/env/filesystem-env.sh'

## Distro versions
export DEBIAN_VERSION='trixie'
export UBUNTU_VERSION='noble' #TODO: Change once Resolute Racoon (26.04) comes out.

## Misc
export ENV_ENV_KERNEL_COMMANDLINE_DIR='/etc/zfsbootmenu/commandline'
export ENV_ZFS_CONFIG_SCRIPT='/etc/zfs/configure-zfs.sh'
