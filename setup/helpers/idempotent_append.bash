#!/usr/bin/env bash
## Append to a file only if the new line doesn't already exist within that file.
function idempotent_append {
    ## $1: What to append
    ## $2: Where to append it
    [[ ! -f "$2" ]] && touch "$2"
    grep -Fqx -- "$1" "$2" || printf '%s\n' "$1" >> "$2"
}
