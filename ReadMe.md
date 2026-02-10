# Miles's Homelab Configs & Scripts

This repo contains scripts, configurations, etc that pertain to my homelab.

## Directories

### settings

Scripts that apply settings.

### setup

Scripts that set up a computer.

#### firmware

Scripts that configure firmware. There are presently two: one that formats NVMe drives to be 4Kn, and one that upgrades the current system's firmwares.

#### partition + format

Scripts that generate either of the following:
* a ZFS pool containing an HDD mirror for bulk data and mirrors of SSD partitions for SLOG and for SVDEV (metadata / small files).
* a ZFS pool containing a mirror of SSD partitions for an operating system, and an mdadm RAID1 of SSD partitions which contains an ESP.

#### initial installation

Scripts that install an operating system to a ZFS root. These scripts are capable of handling Debian and Ubuntu, and use ZFSBootMenu to permit booting directly to a fully-encrypted ZFS root, without exposing `/boot`. The scripts also set up SecureBoot with custom keys, thereby giving all systems fairly robust protection against Evil Maid attacks.

Debian and Ubuntu are *far* from being my favorite distros, but their and their derivatives' official support for ZFS makes them the single greatest choices for serious infrastructure in 2026 apart from NixOS.

#### post-installation + conversion

Scripts that tailor an initial install to a specific machine and use-case. At present, there are three:
* Aetherius, my NAS + home server. (Proxmox)
* Duat + Anubis, my firewall + edge router. (OPNsense virtualized atop Ubuntu Server)
* Morpheus, my AI inference box. (Ubuntu Server)

### software

Scripts that install packages which are not shipped via PPA. Currently, these include:
* STORCLI 3.5 P34
* SAS3FLASH and SAS3IRCU
* IPMICFG

### sourceables

Scripts that can be sourced at the commandline.

### tasks

Scripts that are meant to be run from a server.

### tests

Scripts that test some functionality. At present, the only test is one of ZFS compression speeds and ratios.

## License

Copyright © 2025–2026 Miles Bradley Huff. Licensed publicly per the terms of the GNU General Public License (v3.0 or later).
