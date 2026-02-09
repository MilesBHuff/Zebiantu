#!/usr/bin/env bash
## This script installs IPMICFG on Linux.

CWD=$(pwd)
trap 'cd "$CWD"' EXIT
set -euo pipefail
cd $(dirname "$0")
echo && echo ':: Installing...'

IPMICFG_PATH='/usr/local/sbin/ipmicfg'
cp    Linux/ipmicfg "$IPMICFG_PATH"
chown -Rv root:root "$IPMICFG_PATH"
chmod -Rv 755       "$IPMICFG_PATH"

unset IPMICFG_PATH
echo && echo ':: Installed.'
exit 0
