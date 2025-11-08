#!/usr/bin/env zsh

human_date() {
    date +'%Y-%m-%d %H:%M:%S'
}

file_date() {
    date +'%Y-%m-%dT%Hh%Mm%Ss'
}

readonly BASE_DIR=$(dirname "$(dirname "$(dirname "$(readlink -f "${0}")")")")

# argument parsing
# defaults for arguments
task=spmxv
directory=${BASE_DIR}/$(date +'%Y')/competition
num_groups=9
num_executions=23

usage() {
    echo "usage: collect-competition.sh [-t <task>] [-d <directory>] [-g <num-groups>] [-n <num-executions>] [-h | --help]" 1>&2
    echo "" 1>&2
    echo "Collect raw competition results" 1>&2
    echo "" 1>&2
    echo "script arguments:" 1>&2
    echo "    -h, --help" 1>&2
    echo "        show this help message and exit" 1>&2
    echo "    -t TASK, --task TASK" 1>&2
    echo "        the unique task identifier for which benchmarking is performed (default: ${task})" 1>&2
    echo "    -d DIRECTORY, --directory DIRECTORY" 1>&2
    echo "        the directory which contains the groups tar archives (default: ${directory})" 1>&2
    echo "    -g NUM_GROUPS, --num-groups NUM_GROUPS" 1>&2
    echo "        the maximum number of groups participating in the competition (default: ${num_groups})" 1>&2
    echo "    -n NUM_EXECUTIONS, --num-executions NUM_EXECUTIONS" 1>&2
    echo "        the number of executions for each thread count and problem size (default: ${num_executions})" 1>&2
}

while [ "$1" != "" ]; do
    case $1 in
        -t | --task)
            shift
            task=${1}
            ;;
        -d | --directory)
            shift
            directory=${1}
            ;;
        -g | --num-groups)
            shift
            num_groups=${1}
            ;;
        -n | --num-executions)
            shift
            num_executions=${1}
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

readonly SHELL_EXE=$(readlink -f /proc/$$/exe)
readonly PREPARE=$(dirname "$(readlink -f "${0}")")/prepare/${task}.sh

if [ ! -f "${PREPARE}" ]; then
    echo "ERROR: cannot collect competition results from task '${task}', because the prepare script '${PREPARE}' is missing" 1>&2
    exit 1
fi

directory=$(readlink -f "${directory}")

echo "[$(human_date)] collecting competition results for task ${task}..."

readonly BASE_OUTPUT_DIR=${directory}/results
echo "[$(human_date)] writing output to ${BASE_OUTPUT_DIR}..."
mkdir -p "${BASE_OUTPUT_DIR}"

echo "[$(human_date)] collecting system information..."
{
    echo "Hostname:              $(hostname)"
    lscpu
    numactl --hardware
} > "${BASE_OUTPUT_DIR}/hardware.txt" 2>&1
{
    lsb_release -d
    echo "Kernel Release: $(uname -r)"
} > "${BASE_OUTPUT_DIR}/operating-system.txt" 2>&1

cd "${directory}"
num_threads=64
for group in $(seq "${num_groups}"); do
    taskdir=${task}-group-${group}
    if [ ! -f "${directory}/${taskdir}.tar.gz" ]; then
        echo "[$(human_date)] WARNING: skipping group ${group} because its archive could not be found..."
        continue
    fi
    tar -xzf "${directory}/${taskdir}.tar.gz"

    group_output_dir=${BASE_OUTPUT_DIR}/${group}
    echo "[$(human_date)] writing output to ${group_output_dir} for group ${group}..."
    mkdir -p "${group_output_dir}"
    "${SHELL_EXE}" "${PREPARE}" "${taskdir}"
    (
        cd "${taskdir}"
        if [ -f setup-environment.sh ]; then
            echo "[$(human_date)] setting up the execution environment for group ${group}..."
            source setup-environment.sh > "${group_output_dir}/software.txt" 2>&1
        else
            echo "[$(human_date)] WARNING: no execution environment given for group ${group}..."
        fi

        echo "[$(human_date)] building executable for group ${group} task ${task}..."
        make clean build > "${group_output_dir}/build.txt" 2>&1

        for run in $(seq "${num_executions}"); do
            echo "[$(human_date)] running task ${task} for group ${group} execution ${run}..."
            output_dir=${group_output_dir}/${run}
            mkdir -p "${output_dir}"
            NTHREADS=${num_threads} make run-small > "${output_dir}/small.txt" 2>&1
            NTHREADS=${num_threads} make run-large > "${output_dir}/large.txt" 2>&1
        done
    )
    rm -rf "${taskdir}"
done
echo "[$(human_date)] finished competition collection..."
