#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob
function helptext {
    echo "Usage: configure-deb-distro.bash"
    echo
    echo 'This is a one-shot script that finishes setting up Debian or Ubuntu.'
    echo 'WARN: Although this is intended as a one-shot script, it *should* be more-or-less idempotent; just try to maintain consistent user responses between runs.'
}
## Special thanks to https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Bookworm%20Root%20on%20ZFS.html
## Special thanks to ChatGPT for helping with my endless questions.

###############################
##   B O I L E R P L A T E   ##
###############################
echo ':: Initializing...'

## Base paths
CWD=$(pwd)
ROOT_DIR="$CWD/../.."

## Import functions
declare -a HELPERS=('../helpers/load_envfile.bash' '../helpers/idempotent_append.bash')
for HELPER in "${HELPERS[@]}"; do
    if [[ -x "$HELPER" ]]; then
        source "$HELPER"
    else
        echo "ERROR: Failed to load '$HELPER'." >&2
        exit 1
    fi
done

###########################
##   V A R I A B L E S   ##
###########################

echo ':: Getting the environment...'
## Load and validate environment variables
load_envfile "$ENV_FILESYSTEM_ENVFILE" \
    ENV_NAME_ESP \
    ENV_POOL_NAME_SYS \
    ENV_ZFS_ROOT
load_envfile "$ENV_SETUP_ENVFILE" \
    ENV_FILESYSTEM_ENVFILE \
    ENV_KERNEL_COMMANDLINE_DIR \
    ENV_SETUP_ENVFILE \
    ENV_TUNE_IO_SCRIPT \
    ENV_TUNE_ZFS_SCRIPT \
    DISTRO \
    DEBIAN_VERSION \
    UBUNTU_VERSION \
    TARGET

echo ':: Declaring variables...'
export SYSTEMD_OFFLINE=1
## Misc local variables
export KERNEL_COMMANDLINE=''

#######################
##   M O D U L E S   ##
#######################

for MODULE in ./modules/*/*; do
    echo '________________________________________________________________________________'
    DISPLAY="${MODULE#./modules/}"
    DISPLAY="${DISPLAY%.bash}"
    DISPLAY="${DISPLAY//[0-9]-/}"
    while true; do
        read -rp "Would you like to run this module?: \`$DISPLAY\` (y/n) " ANSWER
        [[ "$ANSWER" == 'y' || "$ANSWER" == 'n' ]] && break
    done
    unset DISPLAY
    [[ $ANSWER == 'y' ]] && source "$MODULE"
done

###################
##   O U T R O   ##
###################

## Snapshot
echo ':: Creating snapshot...'
set +e
zfs snapshot -r "$ENV_POOL_NAME_SYS@initialization"
set -e

## Done
echo ':: Done.'
case "$HOSTNAME" in
    'aetherius'|'morpheus'|'duat') echo "To continue installation, reboot and then execute \`specialize-$HOSTNAME.bash\`." ;;
esac
exit 0
