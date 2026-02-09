#!/usr/bin/env bash
## This script installs STORCLI on Ubuntu and Debian.

CWD=$(pwd)
trap 'cd "$CWD"' EXIT
set -euo pipefail
cd $(dirname "$0")

echo && echo ':: Checking validity...'
export GNUPGHOME=$(mktemp -d)
gpg --import pubKey.asc
gpg --verify storcli*.deb.sig storcli*.deb
rm -rf "$GNUPGHOME"
unset GPUPGHOME

echo && echo ':: Installing...'
dpkg -i storcli*.deb

STORCLI_PATH='/opt/MegaRAID/storcli'
chown -Rv root:root "$STORCLI_PATH"
chmod -Rv 755       "$STORCLI_PATH"

STORCLI_INI_PATH="$STORCLI_PATH/storcliconf.ini"
cp   -fv '../storcliconf.ini' "$STORCLI_INI_PATH"
chown -v root:root            "$STORCLI_INI_PATH"
chmod -v 644                  "$STORCLI_INI_PATH"

STORCLI_ALIAS_PATH='/usr/local/bin/storcli'
cp   -fv '../storcli' "$STORCLI_ALIAS_PATH"
chown -v root:root    "$STORCLI_ALIAS_PATH"
chmod -v 755          "$STORCLI_ALIAS_PATH"

unset STORCLI_PATH STORCLI_INI_PATH STORCLI_ALIAS_PATH
echo && echo ':: Installed:'
dpkg -l | grep -i storcli

# echo ':: Executing...'
# storcli

exit 0
