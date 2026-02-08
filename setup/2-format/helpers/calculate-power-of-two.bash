#!/usr/bin/bash
function helptext {
    echo 'Usage: calculate-power-of-two.bash number'
    echo 'Calculates how many positive powers of two a given number is, and returns that number.'
    echo "Numbers that are not positive integer powers of two return nothing."
}

#FIXME: The script currently doesn't work and is hardcoded to return `12`.
echo 12
exit -1

## Ensure correct number of arguments are passed
if [[ $# != 1 ]]; then
    helptext >&2
    exit 1
fi

## Detect whether an integer
if ! expr "$1" + 0 &>/dev/null; then
    exit 2
fi

## Detect whether positive
if [[ $1 -le 0 ]]; then
    exit 3
fi

## Calculate exponent
declare -i EXPONENT=0
declare -i INTEGER=$1
while [[ $((INTEGER % 2)) -eq 0 ]]; do
    let EXPONENT++
    let INTEGER/=2
done

## Check results
if [[ $INTEGER -eq 1 ]]; then
    echo "$EXPONENT"
    exit 0
else
    exit 4
fi
