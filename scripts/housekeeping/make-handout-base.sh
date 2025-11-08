#!/usr/bin/env zsh

# argument parsing
# defaults for arguments

usage() {
    echo "usage: make-handout-base.sh [-h | --help]" 1>&2
    echo "" 1>&2
    echo "Create a tar archive containing the base directory structure which can be handed out to students" 1>&2
    echo "" 1>&2
    echo "script arguments:" 1>&2
    echo "    -h, --help" 1>&2
    echo "        show this help message and exit" 1>&2
}

while [ "$1" != "" ]; do
    case $1 in
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
    shift
done

readonly BASE_DIR=$(dirname "$(dirname "$(dirname "$(readlink -f "${0}")")")")

BASE_NAME=lab-openmp
tar --directory "${BASE_DIR}" --transform "s|^|${BASE_NAME}/|g" -cvzf "${BASE_NAME}.tar.gz" \
    .Rprofile renv.lock renv/.gitignore renv/activate.R renv/settings.dcf renv/cellar \
    README.md scripts
