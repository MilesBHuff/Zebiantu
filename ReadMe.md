# Miles's Homelab Configs & Scripts

This repo contains scripts, configurations, etc that pertain to my homelab.

## Directories

### Installation

Scripts that install an operating system to a ZFS root. These scripts are capable of handling Debian and Ubuntu, and use ZFSBootMenu to permit booting directly to an encrypted ZFS.

### Partformatition

Scripts that generate either of the following:
* a ZFS pool containing an HDD mirror for bulk data and an SSD mirror for SLOG + SVDEV (metadata / small files).
* a ZFS pool containing an SSD mirror for an operating system, and an mdadm RAID1 containing an ESP.

### Settings

Scripts that apply settings.

### Sourceables

Scripts that can be sourced at the commandline.

### Tasks

Scripts that are meant to be run from a server.

### Tests

Scripts that test some functionality.

## License

Copyright © 2025–2026 Miles Bradley Huff per the terms of the General Public License (v3.0 or later)
