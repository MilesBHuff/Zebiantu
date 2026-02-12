#!/usr/bin/env bash
echo ':: Configuring networking...'

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
    sed -Ei 's/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    systemctl enable ssh
fi; unset DO_IT

echo ':: Configuring Wi-Fi...'

## Configure regulatory domain
read -rp 'Please enter your wireless regulatory domain: ("US" for the USA) ' REGDOM
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE cfg80211.ieee80211_regdom=$REGDOM"
unset REGDOM

## Disable Wi-Fi
read -rp 'Enter "y" to disable Wi-Fi or "n" to leave it untouched. ' DO_IT
if [[ "$DO_IT" == 'y' ]]; then
    apt install -y rfkill
    cat > /etc/udev/rules.d/80-rfkill-wifi.rules <<'EOF'
SUBSYSTEM=="rfkill", ATTR{type}=="wlan", ACTION=="add|change", RUN+="/usr/sbin/rfkill block wifi"
EOF
fi; unset DO_IT
