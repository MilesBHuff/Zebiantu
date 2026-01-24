# Miles's Homelab Configs & Scripts

This repo contains scripts, configurations, etc that pertain to my homelab.

## Partformatition

This directory contains scripts that generate an optimized ZFS pool containing an HDD mirror for bulk data and an SSD mirror for SLOG + SVDEV (metadata / small files), the goal being maximum performance and longevity for relatively minimal hardware.

## Installation

This directory contains scripts that install operating systems to a ZFS root. These scripts are capable of handling Debian and Ubuntu, and use ZFSBootMenu to permit booting directly to an encrypted ZFS.
