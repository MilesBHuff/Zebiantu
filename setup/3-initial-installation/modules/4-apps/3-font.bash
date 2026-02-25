#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`. It must work for both Debian and Ubuntu Server. The parent provides `CWD` and has `set e`. `apt` is used over `apt-get` because this is an attended, semi-interactive install.

## Prepare
echo ':: Preparing to configure better bitmap font...'
OUT='Cozette.psf'
TAG='v.1.30.0'
HASH='aa525b5bef4d36aa85cdc7d38cbade3479078fdaa5c1704d2d5377c313c47954'
cd /tmp
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

## Download
echo ':: Downloading better bitmap font...'
wget -O "$OUT" "https://github.com/the-moonwitch/Cozette/releases/download/$TAG/cozette.psf"
unset TAG
if [[ $(sha256sum "$OUT" | awk '{print $1}') != "$HASH" ]]; then
    echo "$0: '$OUT' has an invalid checksum." >&2
    ## Duplicating cleanup logic instead of using `trap` in order to avoid overwriting parent `trap`.
    cd "$CWD"
    rm -rf "$TMPDIR"
    exit 43 ## Yes, the child is supposed to kill the parent.
fi
unset HASH

## Download
echo ':: Compressing better bitmap font...'
gzip --best -n "$OUT" ## Deletes the original and outputs a `.gz` of it.
NAME="${OUT%.*}"
OUT="$OUT.gz"

## Install
echo ':: Installing better bitmap font...'
INSTALL_DIR='share/consolefonts'
mkdir -p "/usr/local/$INSTALL_DIR"
install -m 0644 "$OUT" "/usr/local/$INSTALL_DIR/"
mkdir -p "/usr/$INSTALL_DIR"
ln -sf "/usr/local/$INSTALL_DIR/$OUT" "/usr/$INSTALL_DIR/"
unset INSTALL_DIR
unset OUT

## Enable
echo ':: Enabling better bitmap font...'
apt install -y console-setup
sed -r \
  -e 's/^[[:space:]]*#?[[:space:]]*(FONTFACE)=.*/\1="'"$NAME"'"/' \
  -e 's/^[[:space:]]*#?[[:space:]]*(FONTSIZE)=.*/\1="6x13"/' \
  -i '/etc/default/console-setup'

## Cleanup
cd "$CWD"
rm -rf "$TMPDIR"
unset TMPDIR
