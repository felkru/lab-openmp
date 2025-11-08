#!/usr/bin/env zsh

# print header if no input file is given
if [ "${#}" -eq 0 ]; then
    echo ',seconds'
    exit
fi

file=${1}
seconds=$(grep 'Time' "${file}" | awk '{ print $3 }')
echo ",${seconds}"
