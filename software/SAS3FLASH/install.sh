#!/usr/bin/env bash
## This script installs SAS3FLASH and SAS3IRCU on Ubuntu and Debian.

CWD=$(pwd)
trap 'cd "$CWD"' EXIT
set -euo pipefail
cd $(dirname "$0")
echo && echo ':: Installing...'

MAIN_PATH='/opt/MegaRAID/installer'
mkdir "$MAIN_PATH"
chown -Rv root:root "$MAIN_PATH"
chmod -Rv 755       "$MAIN_PATH"

SAS3FLASH_PATH="$MAIN_PATH/sas3flash"
chown -Rv root:root "$SAS3FLASH_PATH"
chmod -Rv 755       "$SAS3FLASH_PATH"

SAS3IRCU_PATH="$MAIN_PATH/sas3ircu"
chown -Rv root:root "$SAS3IRCU_PATH"
chmod -Rv 755       "$SAS3IRCU_PATH"

unset MAIN_PATH SAS3FLASH_PATH SAS3IRCU_PATH
echo && echo ':: Installed.'
exit 0
