#!/usr/bin/env bash
# ## Better bitmap font
# #FIXME: It doesn't handle box-drawing characters, and it could be made to handle Powerline characters.
# echo ':: Installing better bitmap font...'
# FILE='/etc/default/console-setup'
# cd /tmp
# REPO='tamzen-font'
# [[ ! -d "$REPO" ]] && git clone "https://github.com/sunaku/$REPO.git"
# cd "$REPO/bdf"
# apt install -y bdf2psf
# mkdir psf
# B2P='/usr/share/bdf2psf'
# bdf2psf --fb Tamzen8x16b.bdf "$B2P/standard.equivalents" "$B2P/ascii.set+$B2P/linux.set+$B2P/useful.set" 512 psf/TamzenBold8x16.psf
# cd psf
# gzip --best *
# cp * /usr/local/share/consolefonts/
# cd /usr/local/share/consolefonts
# rm -rf /tmp/tamzen-font
# ln -s * /usr/share/kbd/consolefonts/
# cat "$FILE" | sed -r 's/^(FONTFACE)=".*/\1="TamzenBold"/' | sed -ir 's/^# (FONTSIZE)=.*/\1="8x16/' '/etc/initramfs-tools/initramfs.conf' > "$FILE.new"
# cd "$CWD"
# unset FILE
