#!/usr/bin/env zsh
# Usage: ./scripts/quick-test.sh [num_threads]
# Default: 96 threads if not specified

PROBLEM_SIZE=${1:-large}
NUM_ITER=${2:-3}
NTHREADS=${3:-96}
TASK_DIR=~/lab-openmp/tasks/merge-sort

echo "[$(date +'%H:%M:%S')] Quick test: ${NTHREADS} threads, 3 iterations, large problem"

srun --account=lect0163 \
     --nodes=1 \
     --ntasks=1 \
     --cpus-per-task=${NTHREADS} \
     --exclusive \
     --time=00:10:00 \
     zsh -c "
         cd ${TASK_DIR}
         source setup-environment.sh
         make clean build
         
         echo '=== Running ${NUM_ITER} iterations ==='
         for i in {1..${NUM_ITER}}; do
             echo \"--- Iteration \$i ---\"
             NTHREADS=${NTHREADS} make run-${PROBLEM_SIZE}
         done
     "

echo "[$(date +'%H:%M:%S')] Test complete"