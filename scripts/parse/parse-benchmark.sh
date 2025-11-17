#!/usr/bin/env zsh

# argument parsing
# defaults for arguments
task=merge-sort
directory=$(pwd)
num_executions=6

usage() {
    echo "usage: parse-benchmark.sh [-t <task>] [-d <directory>] [-n <num-executions>] [-h | --help]" 1>&2
    echo "" 1>&2
    echo "Parse raw benchmarking results into a csv file located in the input directory" 1>&2
    echo "" 1>&2
    echo "script arguments:" 1>&2
    echo "    -h, --help" 1>&2
    echo "        show this help message and exit" 1>&2
    echo "    -t TASK, --task TASK" 1>&2
    echo "        the unique task identifier; has to match an existing result parser to work (default: ${task})" 1>&2
    echo "    -d DIRECTORY, --directory DIRECTORY" 1>&2
    echo "        the directory to parse results from (default: ${directory})" 1>&2
    echo "    -n NUM_EXECUTIONS, --num-executions NUM_EXECUTIONS" 1>&2
    echo "        the number of executions used for each thread count and problem size (default: ${num_executions})" 1>&2
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

# directory name - prepended timestamp = version
readonly VERSION=$(basename "$(realpath -e "${directory}")" | cut -c 22-)
readonly CSV_FILE=${directory}/benchmark.csv
readonly SHELL_EXE=$(readlink -f /proc/$$/exe)
readonly PARSER=$(dirname "$(readlink -f "${0}")")/result-parsers/${task}.sh

if [ ! -f "${PARSER}" ]; then
    echo "ERROR: cannot parse results from task '${task}', because the parser script '${PARSER}' is missing" 1>&2
    exit 1
fi

echo -n 'task,version,run,num_threads,size' > "${CSV_FILE}"
# add task specific header fields
"${SHELL_EXE}" "${PARSER}" >> "${CSV_FILE}"

for run in $(seq "${num_executions}"); do
    for num_threads in 1 2 4 8 12 24 48 72 96; do
        for size in small large; do
            file=${directory}/${run}/${num_threads}/${size}.txt
            if [ ! -f "${file}" ]; then
                echo "WARNING: cannot find the result file '${file}'" 1>&2
                continue
            fi

            echo -n "${task},${VERSION},${run},${num_threads},${size}" >> "${CSV_FILE}"
            # add task specific fields
            "${SHELL_EXE}" "${PARSER}" "${file}" >> "${CSV_FILE}"
        done
    done
done
