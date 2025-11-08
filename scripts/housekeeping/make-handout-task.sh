#!/usr/bin/env zsh

# argument parsing
# defaults for arguments
task=spmxv
version=00_Handout

usage() {
    echo "usage: make-handout-task.sh [-t <task>] [-v <version>] [-h | --help]" 1>&2
    echo "" 1>&2
    echo "Create tar archives of individual tasks which can be handed out to students" 1>&2
    echo "" 1>&2
    echo "script arguments:" 1>&2
    echo "    -h, --help" 1>&2
    echo "        show this help message and exit" 1>&2
    echo "    -t TASK, --task TASK" 1>&2
    echo "        the unique task identifier for which the handout is generated (default: ${task})" 1>&2
    echo "    -v VERSION, --version VERSION" 1>&2
    echo "        the unique identifier of the code version for which the handout is generated (default: ${version})" 1>&2
}

while [ "$1" != "" ]; do
    case $1 in
        -t | --task)
            shift
            task=${1}
            ;;
        -v | --version)
            shift
            version=${1}
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

readonly BASE_DIR=$(dirname "$(dirname "$(dirname "$(readlink -f "${0}")")")")
readonly TASK_DIR=${BASE_DIR}/tasks/${task}

make clean -C "${TASK_DIR}/${version}"
cd "${TASK_DIR}"
tar -cvzf "${task}.tar.gz" --dereference --transform "s|^${version}|tasks/${task}|g" "${version}"
mv "${task}.tar.gz" "${OLDPWD}"
