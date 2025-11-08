#!/usr/bin/env zsh

readonly BASE_DIR=$(dirname "$(dirname "$(dirname "$(dirname "$(readlink -f "${0}")")")")")

taskdir=${1}

cp -r "${BASE_DIR}/tasks/sobel/images" "${taskdir}"
cp -r "${BASE_DIR}/tasks/sobel/utils" "${taskdir}"
