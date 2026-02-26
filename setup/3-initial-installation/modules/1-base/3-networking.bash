#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.
echo ':: Configuring networking...'

## Configure hosts
cat > '/etc/hosts' <<EOF
## Localhost
127.0.0.1 localhost
::1       localhost

## Custom Addresses
127.0.1.1 $HOSTNAME.home.arpa $HOSTNAME
EOF

## Configure WOL
read -rp 'Enter "y" to enable Wake-On-LAN, or "n" to leave it disabled. ' DO_IT
if [[ "$DO_IT" == 'y' ]]; then
    cat > /etc/udev/rules.d/99-wol.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="net", KERNEL=="en*", RUN+="/usr/sbin/ethtool -s %k wol g"
ACTION=="add", SUBSYSTEM=="net", KERNEL=="eth*", RUN+="/usr/sbin/ethtool -s %k wol g"
EOF
fi; unset DO_IT

## Set up `ssh`
read -rp 'Enter "y" to enable ssh, or "n" to leave it disabled. ' DO_IT
if [[ "$DO_IT" == 'y' ]]; then
    apt install -y openssh-server
    idempotent_append 'PermitRootLogin prohibit-password' '/etc/ssh/sshd_config.d/disable-root.conf'
    systemctl enable ssh
fi; unset DO_IT

## Switch to NetworkManager
echo ':: Switching to NetworkManager...'
echo 'Static IPs should be defined in your Layer 3 switch, not at the client level.'
## NetworkManager is mature, and it is robust at handling DHCP; I’ve chosen therefore to standardize on it.
## Compared to simpler networking options, NetworkManager should be the most turnkey and the most self-healing.
case $DISTRO in
    1)
        ## Debian
        apt purge -y ifupdown || true
        cat > /etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback
EOF
        apt install network-manager
        systemctl enable NetworkManager
        # systemctl start NetworkManager ## Shouldn't start/stop from chroot.
        ;;
    2)
        ## Ubuntu
        apt install -y networkmanager
        mkdir -p /etc/netplan ## Just to be safe.
        cat > /etc/netplan/99-use-networkmanager.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
EOF
        # systemctl stop systemd-networkd ## Shouldn't start/stop from chroot.
        # systemctl start NetworkManager ## Shouldn't start/stop from chroot.
        # netplan apply ## Shouldn't run from chroot. (It'll get run during boot anyway.)
        systemctl enable NetworkManager
        systemctl disable systemd-networkd
        # apt purge systemd-networkd ## Also removes the `ubuntu-server` metapackage, which is not a desirable outcome.
        ;;
esac

## Configure regulatory domain
echo ':: Configuring Wi-Fi...'
read -rp 'Please enter your wireless regulatory domain: ("US" for the USA) ' REGDOM
REGDOM="${REGDOM^^}"
REGDOM="${REGDOM//[[:space:]]/}"
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE cfg80211.ieee80211_regdom=$REGDOM"
unset REGDOM

## Disable Wi-Fi
read -rp 'Enter "y" to disable Wi-Fi or "n" to leave it untouched. ' DO_IT
if [[ "$DO_IT" == 'y' ]]; then
    apt install -y rfkill
    cat > /etc/udev/rules.d/80-rfkill-wifi.rules <<'EOF'
SUBSYSTEM=="rfkill", ATTR{type}=="wlan", ACTION=="add|change", RUN+="/usr/sbin/rfkill block wifi"
EOF
    # nmcli radio wifi off ## Shouldn't work in chroot.
    # nmcli general reload ## Shouldn't work in chroot.
fi
unset DO_IT
