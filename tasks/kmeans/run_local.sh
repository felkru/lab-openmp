#!/usr/bin/env zsh
# Usage: ./tasks/kmeans/run_local.sh [small|mid|large] [num_iter]
# Example: ./tasks/kmeans/run_local.sh small 1

PROBLEM_SIZE=${1:-small}
NUM_ITER=${2:-1}
TASK_DIR=${PWD}/tasks/kmeans

echo "[$(date +'%H:%M:%S')] Local GPU Run (Device 1): ${PROBLEM_SIZE} problem, ${NUM_ITER} iterations"

cd ${TASK_DIR}

# Load required modules
module purge
module load GCCcore/14.2.0 LLVM/20.1.7 CUDA/12.6.3

# Build with Clang++ for OpenMP Offloading
# Note: Ensure CXX=clang++ is passed
make release CXX=clang++

# Run on GPU 1 (Local H100)
# Passing NITERS to override Makefile default if needed, though Makefile uses args for run-*
# The Makefile run targets expect arguments, or we can just use the make target which uses variables.
# Let's rely on the Makefile's run command but pass variables.
CUDA_VISIBLE_DEVICES=1 make run-${PROBLEM_SIZE} CXX=clang++ NITERS=${NUM_ITER}

echo "[$(date +'%H:%M:%S')] Run Complete"
