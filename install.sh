#!/bin/sh
mkdir -p /etc/exports.d
exec apt install -y zfsutils-linux sanoid smartmontools
