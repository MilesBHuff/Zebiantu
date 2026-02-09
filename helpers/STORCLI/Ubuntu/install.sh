#!/usr/bin/env bash
CWD=$(pwd)
trap 'cd "$CWD"' EXIT
set -e
cd $(dirname "$0")

echo && echo ':: Importing public key...'
gpg --import pubKey.asc
echo && echo ':: Checking signature...'
gpg --verify storcli*.deb.sig storcli*.deb

echo && echo ':: Installing...'
sudo dpkg -i storcli*.deb

STORCLI_PATH='/opt/MegaRAID/storcli'
sudo chown -Rv root:root "$STORCLI_PATH"
sudo chmod -Rv 755       "$STORCLI_PATH"

STORCLI_INI_PATH="$STORCLI_PATH/storcliconf.ini"
sudo cp   -fv '../storcliconf.ini' "$STORCLI_INI_PATH"
sudo chown -v root:root            "$STORCLI_INI_PATH"
sudo chmod -v 644                  "$STORCLI_INI_PATH"

STORCLI_ALIAS_PATH='/usr/local/bin/storcli'
sudo cp   -fv '../storcli' "$STORCLI_ALIAS_PATH"
sudo chown -v root:root    "$STORCLI_ALIAS_PATH"
sudo chmod -v 755          "$STORCLI_ALIAS_PATH"

echo && echo ':: Installed:'
dpkg -l | grep -i storcli

# echo ':: Executing...'
# storcli

exit 0
