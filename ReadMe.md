# Zebiantu — a `.deb` distro spin
This repo contains a series of scripts that install Debian/Ubuntu and configure it to meet my needs. The divergence is sufficiently great that this constitutes a custom spin of those distros, one I am terming "Zebiantu" — a blend of "**Z**FS", "D**ebia**n", and "Ubu**ntu**".

Why go to such lengths? Well, a number of core reasons:
* Ubuntu and multiple Debian derivatives have first-class ZFS support, and nothing else does. I want Linux and I want ZFS; this effectively pigeonholes me here.
* The stock distros do not have an even remotely acceptable boot-chain — they are convoluted, inelegant, and insecure. Yet, there is no reason for them to be: ZFSBootMenu allows encrypted root-on-ZFS (`/boot` included), UEFI allows exclusively using your own custom keys instead of Microsoft's, and TPM auto-unlocking exists and can be used if appropriate.
* A setup that is not scripted is a setup that is not documented or reproducible. There are so many things that need configuring when you are earnestly setting up a ZFS-based system that it would be foolish to proceed without scripting it.

## Dependencies
* Zebiantu is designed to utilize either Debian 13 "Trixie" or Ubuntu 24.04 "Noble Numbat" as its base.
* Zebiantu is built around ZFS 2.3.

## Directories

### .
Repo meta. Of particular note are the two environment files:
* `filesystem-env`: Variables relating to disks and filesystems (mostly ZFS)
* `setup-env`: Variables relating to the setup process

### settings
Scripts that apply settings.
* `tune-io`: This script can be run manually or via udev rule. It helps ensure that various settings, mainly queue depth, are set optimally per the characteristics of each disk, and in consideration of the ZFS configuration.
* `tune-zfs`: This script is run manually, and generates a `/etc/modprobe.d/zfs-customized.conf` file with settings optimized for the system's ZFS setup.

### setup
Scripts that set up a computer, run from that computer interactively and in-person.

#### firmware
Scripts that configure firmware. There are presently two:
* `low-level-format`: This formats NVMe drives to be 4Kn. (It's not the 2000s anymore; virtually everything supports 4Kn now. I want to be rid of the 512e specter.)
* `upgrade-firmware`: This uses `fwupd` to upgrade system firmware.

#### partition + format
Scripts that produce one of the following:
* `os-pool`: a ZFS pool containing a mirror of SSD partitions for an operating system, and an mdadm RAID1 of SSD partitions which contains an ESP.
* `nas-pool`: a ZFS pool containing an HDD mirror for bulk data and mirrors of SSD partitions for SLOG and for SVDEV (metadata / small files).
* `das-pool`: a ZFS pool containing one or more HDDs, intended to be used as a backup of `nas-pool`.

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
        * `zfs`: Configures the system to utilize ZFS.
        * `fs`: Configures the system to utilize additional filesystems.
        * `maintenance`: Configures periodic trim, scrub, SMART, etc.
        * `snapshots`: Configures regularly taking and pruning snapshots with timescales appropriate to workload.‡
        * `mount-options`: Make `lazytime` and `noatime` act as *de facto* defaults across the system.
        * `fhs`: Tweaks the system's filesystem hierarchy.
        * `memory`: Configures system memory: sets up various memory-based filesystems, like `/tmp` and swap; and **configures a tiered memory compression scheme with lighter compression for hotter pages and heavier compression for colder pages, thus expanding total effective memory by as much as practical.**
    * `boot`: Configure the boot chain. The end-result is strongly resistant to Evil-Maid attacks, and the overall architecture is much-more-elegant than anything shipping today (early 2026). And because it's based around ZFSBootMenu, it is easy to recover from any issues: Just put a vanilla ZBM image on a flash drive, temporarily disable SecureBoot, manually type your password, and fix the issue.
        * `esp-with-zbm.bash`: Sets up an ESP containing a custom ZFSBootMenu image that unlocks **a Linux system whose entire root (including `/boot`) is on encrypted ZFS.**
        * `secureboot-with-zbm.bash`: **Sets up SecureBoot using *only* self-signed keys. It includes hooks to auto-sign ZFSBootMenu and kernel modules.**
        * `tpm-autounlock-with-zbm.bash`: Optionally **sets up TPM auto-unlocking for ZFSBootMenu+SecureBoot.** *(Only used on `duat`, the edge router.)*
        * `hibernation`: Disables stock hibernation/resume, then optionally **allows hibernation by way of temporary swap zvol** if the system uses dracut to build its initramfs.
    * `apps`: Add and configure various applications.
        * `packages`: Install all sorts of things that the system will need.
        * `time`: Configure the system's time daemon.
        * `font`: Give the system a better text-mode font.
        * `tty`: Configures tty9 to run `btop` and tty10 to display the system console; and adds an easy way to display VM consoles on tty11+.
        * `integrity`: [WIP] Configures some automatic integrity checks.
    * `config`: Various supplementary configurations.
        * `sizes`: Disables compression across the operating system to let ZFS compression take over. Also limits the sizes of logs.
        * `sysctl`: Various sysctl tweaks. Improves security, reduces logspam, and improves I/O performance.
        * `commandline`: Configures the kernel commandline, taking care to organize and deduplicate the arguments provided by the other modules.

* *† Debian and Ubuntu are *far* from being my favorite distros, but their and their derivatives' official (read: kernel + ZFS released together in lockstep) support for ZFS makes them the single greatest choices for serious infrastructure in 2026, apart from perhaps NixOS.*
* *‡ If you convert to Proxmox, try to avoid using Proxmox's builtin snapshotting feature; let `sanoid`/`syncoid` handle everything.*

#### post-installation
Scripts that tailor an initial install to a specific machine and use-case. At present, there are three:
* `configure-aetherius`: For my NAS + home server.
    * Installs various necessary applications
    * Installs proprietary software for applicable enterprise hardware
    * Sets up the TRNG
    * [WIP] Configures auto-shutdown when remaining UPS runtime is under 5 minutes.
    * Schedule maintenance tasks for specific times.
    * Tweaks some settings.
* `configure-duat`: For my edge router / firewall.
    * Installs various necessary applications.
    * Sets up network interface passthrough.
    * Sets up an OPNsense VM.
    * [WIP] Configures auto-shutdown when remaining UPS runtime is under 5 minutes.
    * Configures auto-restarts (because no ECC).
    * Schedule maintenance tasks for specific times.
    * Tweaks some settings.
* `configure-morpheus`: For my AI inference box.
    * Installs various necessary applications.
    * [WIP] installs various things necessary for running inference (including ROCm).
    * [WIP] Configures auto-shutdown when remaining UPS runtime is under 5 minutes.
    * Configures auto-restarts (because no ECC).
    * Schedule maintenance tasks for specific times.
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

## Upcoming features
These will be implemented once Zebiantu is feature-complete.
* ZFS 2.4 support
    * `nas-pool` partitioned svdev + SLOG mirror is simplified to a single whole-disk svdev mirror, using the new ZIL-on-svdev feature.
    * Automatic defragmentation: a daemon that periodically checks file fragmentation for files physically located on an HDD, and runs `zfs rewrite` on anything found to have significant fragmentation.
* dracut vs initramfs
    * Zebiantu works on both Ubuntu and Debian, but that is true only so long as both use the same init. Ubuntu made the switch in 25.10, and Debian plans to in 2027. Zebiantu will not support Ubuntu 26.04 until Debian 14 and Proxmox VE 10 have released.

## Notes
* Initially, these scripts supported only Debian, as I was using them just to set up Proxmox VE on a fully-encrypted and SecureBoot-secured root. But as my needs grew, I had to expand the scripts to support Ubuntu Server (which has better ZFS support than raw Debian), as I have several machines that need ZFS but do not need Proxmox. After writing these scripts, I have come to realize that I do not actually need Proxmox; I'm already doing everything it does, but manually. And so, arguably, it is best for me *now* to standardize on Ubuntu Server and drop support for Debian and Proxmox; but I've already done the work to implement Debian support, and I like that these scripts give you the option to choose for yourself which to use; so at least for the *present*, I plan to continue supporting Debian, but I will drop that support when a technical divergence between Ubuntu and Debian makes continuing to support both excessively complex.
* Why `sanoid`/`syncoid` instead of `zrepl`?  While `zrepl` *is* technically  superior, its use of YAML over plaintext configs makes it intractable for a shell-based installer such as this.
* Once I have learned NixOS, I should like to reimplement everything from Zebiantu in Nix. This would enable post-installation settings sync, and it would permit things (like `zrepl`) that are not viable in a shell-based installation system.

## License
Copyright © 2025–2026 Miles Bradley Huff. Licensed publicly per the terms of the GNU General Public License (v3.0 or later).
