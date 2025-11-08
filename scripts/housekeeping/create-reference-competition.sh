#!/usr/bin/env zsh

readonly BASE_DIR=$(dirname "$(dirname "$(dirname "$(readlink -f "${0}")")")")

# argument parsing
# defaults for arguments
task=spmxv
directory=${BASE_DIR}/2000/competition

usage() {
    echo "usage: create-reference-competition.sh [-t <task>] [-v <version>] [-h | --help]" 1>&2
    echo "" 1>&2
    echo "Create competition ready tar archives to measure the reference implementations" 1>&2
    echo "" 1>&2
    echo "script arguments:" 1>&2
    echo "    -h, --help" 1>&2
    echo "        show this help message and exit" 1>&2
    echo "    -t TASK, --task TASK" 1>&2
    echo "        the unique task identifier for which the tar archives are generated (default: ${task})" 1>&2
    echo "    -d DIRECTORY, --directory DIRECTORY" 1>&2
    echo "        the directory in which to place the groups tar archives (default: ${directory})" 1>&2
}

while [ "$1" != "" ]; do
    case $1 in
        -t | --task)
            shift
            task=${1}
            ;;
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

readonly MAX_NUM_VERSIONS=99

readonly TASK_DIR=${BASE_DIR}/tasks/${task}

cd "${BASE_DIR}"
mkdir -p "${directory}"
for version in $(seq "${MAX_NUM_VERSIONS}"); do
    padded_version=$(printf "%0${#MAX_NUM_VERSIONS}d" "${version}")
    if ! find "${TASK_DIR}" -maxdepth 1 -mindepth 1 -type d -name "${padded_version}_*" | grep -q .; then
        continue
    fi

    "${BASE_DIR}/scripts/housekeeping/make-handout-task.sh" -t "${task}" -v "$(basename "${TASK_DIR}/${padded_version}_"*)"
    mv "${task}.tar.gz" "${TMPDIR}"
    cd "${TMPDIR}"
    tar -xzf "${task}.tar.gz"
    (
        cd "tasks/${task}"
        GROUP=${version} make archive
        mv "${task}-group-${version}.tar.gz" "${directory}"
    )
    rm -rf "${task}.tar.gz" "tasks/${task}"
done
