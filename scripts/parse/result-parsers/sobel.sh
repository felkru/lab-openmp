#!/usr/bin/env zsh

# print header if no input file is given
if [ "${#}" -eq 0 ]; then
    echo ',milliseconds'
    exit
fi

file=${1}
milliseconds=$(grep 'took' "${file}" | awk '{ print $6 }')
echo ",${milliseconds}"
