# Miles's Homelab Configs & Scripts
This repo contains scripts, configurations, etc that pertain to my homelab.

## Directories

### settings
Scripts that apply settings.
* `tune-io`: This script can be run manually or via udev rule. It helps ensure that various settings, mainly queue depth, is set optimally per the characteristics of each disk, and in consideration of the ZFS configuration.
* `tune-zfs`: This script is run manually, and generates a `/etc/modprobe.d/zfs-customized.conf` file with settings optimized for the system's ZFS setup.

### setup
Scripts that set up a computer. They diverge so much from base Debian/Ubuntu/Proxmox that they might as well constitute a "Milex" spin of `.deb` distros.

#### firmware
Scripts that configure firmware. There are presently two:
* `low-level-format`: This formats NVMe drives to be 4Kn. (It's not the 2000s anymore; virtually everything supports 4Kn now. I want to be rid of the 512e specter.)
* `upgrade-firmware`: This uses `fwupd` to upgrade system firmware.

#### partition + format
Scripts that generate either of the following:
* a ZFS pool containing an HDD mirror for bulk data and mirrors of SSD partitions for SLOG and for SVDEV (metadata / small files).
* a ZFS pool containing a mirror of SSD partitions for an operating system, and an mdadm RAID1 of SSD partitions which contains an ESP.

#### initial installation
Scripts that install an operating system to a ZFS root. These scripts are capable of handling Debian and Ubuntu.† **(Particularly stand-out features are emboldened.)**
* `initialize-deb-distro`: Lays the groundwork for and initializes a `chroot` to the target system.
* `install-deb-distro-from-chroot`: Executes a series of "modules" to set up a `.deb`-based distro from `chroot`.
    * `base`: Set up the basic features of the operating system.
        * `apt`: Configures `apt` and `full-upgrade`s the system, to avoid any partial upgrades during installation.
        * `foundations`: Installs things that are foundational to the system and the rest of the script.
        * `networking`: Configures networking.
        * `config`: Various mostly-interactive system configurations — the typical stuff you deal with when installing a new operating system.
    * `fs`: Configure filesystems.
        * `zsh`: Configures the system to utilize ZFS.
        * `maintenance`: [WIP] Configures periodic trim, scrub, SMART, etc.
        * `shapshots`: [WIP] Configures regularly taking and pruning snapshots. Retention is per the Tower of Hanoi.
        * `mount-options`: Make `lazytime` and `noatime` act as *de facto* defaults across the system.
        * `fsh`: Modifies the system's filesystem hierarchy to maximize the utility of ZFS's snapshots.
        * `mem-fs`: Sets up various memory-based filesystems, like `/tmp` and swap. Configures zswap as a lightly-compressed hot cache and zram swap as a moderately-compressed cold cache.
    * `boot`: Configure the boot chain. The end-result is strongly resistant to Evil-Maid attacks, and the overall architecture is much-more-elegant than anything shipping today (early 2026). And because it's based around ZFSBootMenu, it is easy to recover from any issues: Just put a vanilla ZBM image on a flash drive, temporarily disable SecureBoot, manually type your password, and fix the issue.
        * **`esp-with-zbm.bash`: Sets up an ESP containing a custom ZFSBootMenu image that unlocks a Linux system whose entire root (including `/boot`) is on encrypted ZFS.**
        * **`secureboot-with-zbm.bash`: Sets up SecureBoot using ONLY self-signed keys. It includes hooks to auto-sign ZFSBootMenu and kernel modules.**
        * **`tpm-autounlock-with-zbm.bash`: [optional] Sets up TPM auto-unlocking for ZFSBootMenu+SecureBoot.** (Only used on the edge router.)
        * **`hibernation`: [WIP] Allows hibernation by way of temporary swap zvol.**
    * `apps`: Add and configure various applications.
        * `packages`: Install all sorts of things that the system will need.
        * `time`: [WIP] Configure the system's time daemon.
        * `font`: [WIP] Give the system a better text-mode font.
        * `tty`: Configures tty10 to display the system console, and adds an easy way to display VM consoles on tty11+.
        * `integrity`: [WIP] Configures some automatic integrity checks.
    * `config`: Various supplementary configurations.
        * `sizes`: Disables compression across the operating system to let ZFS compression take over. Also limits the sizes of logs.
        * `sysctl`: Various sysctl tweaks. Improves security, reduces logspam, and improves I/O performance.
        * `commandline`: Configures the kernel commandline, taking care to organize and deduplicate the arguments provided by the other modules.

*† (Debian and Ubuntu are *far* from being my favorite distros, but their and their derivatives' official (read: in-kernel) support for ZFS makes them the single greatest choices for serious infrastructure in 2026, apart from perhaps NixOS.)*

#### post-installation + conversion
Scripts that tailor an initial install to a specific machine and use-case. At present, there are three:
* `configure-aetherius`: For my NAS + home server.
    * Installs various necessary applications
    * Installs proprietary software for applicable enterprise hardware
    * Sets up the TRNG
    * [WIP] Configures auto-hibernation on low-battery UPS
    * Tweaks some settings.
* `configure-duat`: For my edge router / firewall.
    * Installs various necessary applications.
    * Switches to NetworkManager.
    * Sets up network interface passthrough.
    * Sets up an OPNsense VM.
    * [WIP] Configures auto-hibernation on low-battery UPS.
    * [WIP] Configures auto-restarts (because no ECC).
    * Tweaks some settings.
* `configure-morpheus`: For my AI inference box.
    * Installs various necessary applications.
    * [WIP] installs various things necessary for running inference (including ROCm).
    * [WIP] Configures auto-hibernation on low-battery UPS.
    * [WIP] Configures auto-restarts (because no ECC).
    * Tweaks some settings.

#### conversion
Scripts that convert Debian / Ubuntu into a derivative.
* `convert-debian-to-proxmox`: Self-explanatory. Used on Aetherius.

### software
Scripts that install packages which are not shipped via PPA. Currently, these include:
* STORCLI 3.5 P34
* SAS3FLASH and SAS3IRCU
* IPMICFG

### sourceables
Scripts that can be sourced at the commandline.
* `auto-hardlink`: This is a one-shot deduplication script wrapping `rdfind`. It recursively compares all the files in a directory, and after making super-duper-extra-sure that it's found a duplicate, it converts one of the two copies into a hardlink.
* `rclonoid`: Uses `rclone` to reliably and quickly send data from one location to another while maintaining literally all properties. Primarily used as a way to transfer data from old drives onto the NAS.
* `rsyncoid`: Uses `rsync` to do what `rclonoid` does, but slower and less-elegantly.

### tasks
Scripts meant to standardize and simplify specific recurrent actions.
* `rclonoid-from-das-to-nas`: This is a way to resilver from backup, after recreating the NAS's zpool from scratch. Used a couple times while optimizing pool and dataset properties.
* `replicate-zfs`: Uses `zfs send | recv` to send data between two zpools that share history. You can select between a few different options for how to do this. The script is still somewhat experimental.

### tests
Scripts that test some functionality. At present, the only test is one of ZFS compression speeds and ratios.

## License
Copyright © 2025–2026 Miles Bradley Huff. Licensed publicly per the terms of the GNU General Public License (v3.0 or later).
