#!/usr/bin/env zsh

human_date() {
    date +'%Y-%m-%d %H:%M:%S'
}

file_date() {
    date +'%Y-%m-%dT%Hh%Mm%Ss'
}

# argument parsing
# defaults for arguments
task=spmxv
version=release
num_executions=23

usage() {
    echo "usage: collect-benchmark.sh [-t <task>] [-v <version>] [-n <num-executions>] [-h | --help]" 1>&2
    echo "" 1>&2
    echo "Collect raw benchmarking results" 1>&2
    echo "" 1>&2
    echo "script arguments:" 1>&2
    echo "    -h, --help" 1>&2
    echo "        show this help message and exit" 1>&2
    echo "    -t TASK, --task TASK" 1>&2
    echo "        the unique task identifier for which benchmarking is performed (default: ${task})" 1>&2
    echo "    -v VERSION, --version VERSION" 1>&2
    echo "        the unique identifier for the benchmarked code version (default: ${version})" 1>&2
    echo "    -n NUM_EXECUTIONS, --num-executions NUM_EXECUTIONS" 1>&2
    echo "        the number of executions for each thread count and problem size (default: ${num_executions})" 1>&2
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

readonly BASE_DIR=$(dirname "$(dirname "$(dirname "$(readlink -f "${0}")")")")
readonly TASK_DIR=${BASE_DIR}/tasks/${task}
readonly BASE_OUTPUT_DIR=${BASE_DIR}/benchmarking/${task}/$(file_date)-${version}

echo "[$(human_date)] starting benchmark execution for task ${task} version ${version}..."

echo "[$(human_date)] writing output to ${BASE_OUTPUT_DIR}..."
mkdir -p "${BASE_OUTPUT_DIR}"

echo $TASK_DIR

if [ -f "${TASK_DIR}/setup-environment.sh" ]; then
    echo "[$(human_date)] setting up the execution environment..."
    source "${TASK_DIR}/setup-environment.sh" > "${BASE_OUTPUT_DIR}/software.txt" 2>&1
fi

echo "[$(human_date)] collecting system information..."
{
    echo "Hostname:              $(hostname)"
    lscpu
    numactl --hardware
} > "${BASE_OUTPUT_DIR}/hardware.txt" 2>&1
{
    lsb_release -d
    echo "Kernel Release: $(uname -r)"
} >> "${BASE_OUTPUT_DIR}/operating-system.txt" 2>&1

echo "[$(human_date)] rebuilding executable for task ${task}..."
cd "${TASK_DIR}"
make clean build > "${BASE_OUTPUT_DIR}/build.txt" 2>&1

for run in $(seq "${num_executions}"); do
    for num_threads in 1 2 4 8 12 24 48 72 96; do
        echo "[$(human_date)] running task ${task} execution ${run} with ${num_threads} threads..."
        output_dir=${BASE_OUTPUT_DIR}/${run}/${num_threads}
        mkdir -p "${output_dir}"
        NTHREADS=${num_threads} make run-small > "${output_dir}/small.txt" 2>&1
        NTHREADS=${num_threads} make run-large > "${output_dir}/large.txt" 2>&1
    done
done
echo "[$(human_date)] finished benchmark execution..."
