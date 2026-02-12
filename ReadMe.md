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

Scripts that install an operating system to a ZFS root. These scripts are capable of handling Debian and Ubuntu. These are *far* from being my favorite distros, but their and their derivatives' official support for ZFS makes them the single greatest choices for serious infrastructure in 2026 apart from NixOS.

* `initialize-deb-distro`: Lays the groundwork for and initializes a `chroot` to the target system.
* `install-deb-distro-from-chroot`: Executes a series of "modules" to set up a `.deb`-based distro from `chroot`.
    * `base`: Set up the basic features of the operating system.
        * `apt`: Configures `apt` and `full-upgrade`s the system, to avoid any partial upgrades during installation.
        * `foundations`: Installs things that are foundational to the system and the rest of the script.
        * `networking`: Configures networking.
        * `config`: Various mostly-interactive system configurations — the typical stuff you deal with when installing a new operating system.
    * `fs`: Configure filesystems.
        * `zsh`: Configures the system to utilize ZFS.
        * `mount-options`: Make `lazytime` and `noatime` act as *de facto* defaults across the system.
        * `fsh`: Modifies the system's filesystem hierarchy to maximize the utility of ZFS's snapshots.
        * `mem-fs`: Sets up various memory-based filesystems, like `/tmp` and swap. Configures zswap as a lightly-compressed hot cache and zram swap as a moderately-compressed cold cache.
    * `boot`: Configure the boot chain.
        * `esp-with-zbm.bash`: Sets up an ESP containing a custom ZFSBootMenu image that unlocks a Linux system whose entire root (including `/boot`) is on encrypted ZFS.
        * `secureboot-with-zbm.bash`: Sets up SecureBoot using ONLY self-signed keys. It includes hooks to auto-sign ZFSBootMenu and kernel modules.
        * `tpm-autounlock-with-zbm.bash`: [optional] Sets up TPM auto-unlocking for ZFSBootMenu+SecureBoot.
        * `hibernation`: Allows hibernation by way of temporary swap zvol.
    * `apps`: Add and configure various applications.
        * `packages`: Install all sorts of things that the system will need.
        * `time`: Configure the system's time daemon.
        * `font`: Give the system a better text-mode font.
        * `tty`: Configures tty10 to display the system console, and adds an easy way to display VM consoles on tty11+.
    * `config`: Various supplementary configurations.
        * `sizes`: Disables compression across the operating system to let ZFS compression take over. Also limits the sizes of logs.
        * `sysctl`: Various sysctl tweaks. Improves security, reduces logspam, and improves I/O performance.
        * `commandline`: Configures the kernel commandline, taking care to organize and deduplicate the arguments provided by the other modules.

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
