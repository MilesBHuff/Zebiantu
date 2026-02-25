#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.
apt install -y \
    clamav \
    debsums \
    rkhunter

#NOTE: ClamAV scans are basically scrubs in terms of intensity, so they should be run only very sparingly. It's probably best to find some way to only run them on new I/O — maybe every time a file is written to, it is added to a "to scan" list, and ClamAV then gradually scans that list when the system is idle.
#NOTE: debsums is of only moderate utility — ZFS checksums prevent latent corruption, debsums has false positives resulting from normal system use, and any attacks found this way are likely to indicate root-level exploits, which if present means we've already lost.
#NOTE: rkhunter is of relatively limited efficacy nowadays, but it doesn't hurt to have it.

#TODO: Configure ClamAV
