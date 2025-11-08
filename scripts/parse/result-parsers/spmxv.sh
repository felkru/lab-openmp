#!/usr/bin/env zsh

# print header if no input file is given
if [ "${#}" -eq 0 ]; then
    echo ',seconds,mflops'
    exit
fi

file=${1}
seconds=$(grep 'Mean kernel time:' "${file}" | awk '{ print $5 }')
mflops=$(grep 'Total MFlops' "${file}" | awk '{ print $3 }')
echo ",${seconds},${mflops}"
