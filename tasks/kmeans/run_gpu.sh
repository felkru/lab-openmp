#!/usr/bin/env zsh
# Usage: ./tasks/kmeans/run_gpu.sh [small|mid|large] [num_iter] [nthreads]
# Default: small problem, 1 iterations and 1 threads if none is specified

PROBLEM_SIZE=${1:-small}
NUM_ITER=${2:-1}
NTHREADS=${3:-4}
TASK_DIR=${PWD}/tasks/kmeans

echo "[$(date +'%H:%M:%S')] GPU test: ${NTHREADS} threads, ${NUM_ITER} iterations, ${PROBLEM_SIZE} problem"

# -23g is required for GPU access as per instructions
srun --account=lect0163 \
     --nodes=1 \
     --ntasks=1 \
     --cpus-per-task=${NTHREADS} \
     --gres=gpu:1 \
     --exclusive \
     --time=00:10:00 \
     -23g \
     zsh -c "
         ulimit -n 2048
         cd ${TASK_DIR}
         module purge
         module load GCCcore/14.2.0 LLVM/20.1.7 CUDA/12.6.3
         make clean release
         
         echo '=== Running ${NUM_ITER} iterations ==='
         for i in {1..${NUM_ITER}}; do
             echo \"--- Iteration \$i ---\"
             make run-${PROBLEM_SIZE}
         done
     "

echo "[$(date +'%H:%M:%S')] Test complete"
