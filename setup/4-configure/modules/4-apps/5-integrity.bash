#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script.

## I have run ClamAV on a production server at work before and found a credit card skimmer in one of the Wordpress sites; so the stereotype that ClamAV is only for email is wrong.
apt install -y clamav clamav-base clamav-daemon clamav-freshclam clamdscan
systemctl enable clamav-freshclam
systemctl enable clamav-daemon
#NOTE: ClamAV scans are basically scrubs in terms of intensity, so they should be run only very sparingly. It's probably best to find some way to only run them on new I/O in specific datasets — maybe every time a file is written to, it is added to a "to scan" list, and ClamAV then gradually scans that list when the system is idle?
#TODO: Configure ClamAV

## rkhunter sounds nice, but it produces many false-positives on modern Linux, and is maybe a bit outdated in its threat model.
# apt install -y rkhunter
# sudo rkhunter --update
# sudo rkhunter --propupd
#TODO: Automate updates.

## chkrootkit has the same caveats as rkhunter.
# apt install -y chkrootkit
#TODO: Automate updates.

## debsums is of only moderate utility — ZFS checksums prevent latent corruption, debsums has false positives resulting from normal system use, and any attacks found this way are likely to indicate root-level exploits, which if present means we've already lost.
apt install -y debsums
#NOTE: The RHEL equivalent is `rpm -Va`.
