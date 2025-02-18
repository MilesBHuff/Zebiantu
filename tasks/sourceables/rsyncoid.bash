#!/usr/bin/env bash
function rsyncoid {
    function helptext {
        echo "Usage: rsyncoid <source> <destination>"
    }

    if [[ -z "$1" || -z "$2" ]]; then
        helptext >&2
        return 1
    fi

    if ! command -v rsync &>/dev/null; then
        echo 'Error: `rsync` not in `PATH`.' >&2
        return 2
    fi

    local LOGDIR="${RSYNCOID_LOGDIR:-/tmp/rsyncoid}"
    mkdir -p "$LOGDIR" > /dev/null 2>&1 || {
        echo "Error: Unable to create '$LOGDIR'." >&2
        return 3
    }
    [[ ! -x "$LOGDIR" || ! -w "$LOGDIR" || ! -r "$LOGDIR" ]] && {
        echo "Error: Insufficient access to '$LOGDIR'." >&2
        return 4
    }

    local TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    rsync \
        -ahAEHPSX --append-verify \
        "$1" "$2" \
        2> >(tee "$LOGDIR/rsyncoid_$TIMESTAMP.stderr.txt" >&2)
}
