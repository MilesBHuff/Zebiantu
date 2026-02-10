#!/usr/bin/env bash
## Source a script containing environment variables, and validate the existence of all the variables we're requesting.
function load_envfile {
    ENV_FILE="$1"; unset 1
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    else
        echo "ERROR: Missing '$ENV_FILE'." >&2
        exit 2
    fi

    declare -a ENV_VARS="${@:2}"; unset 2
    for ENV_VAR in "${ENV_VARS[@]}"; do
        if [[ -z "$ENV_VAR" ]]; then
            echo "ERROR: Missing variable in '$ENV_FILE'!" >&2
            exit 3
        fi
    done
}
