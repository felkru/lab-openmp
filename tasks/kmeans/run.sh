#!/usr/bin/env zsh

### Job configuration
#SBATCH --job-name=k-run
#SBATCH --account=lect0163
#SBATCH --output=benchmark_output_%j.log
#SBATCH --error=benchmark_error_%j.log
#SBATCH --time=00:60:00
#SBATCH --mem=0
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --gres=gpu:4
#SBATCH --cpus-per-task=16


module purge
# Load CUDA (provides nvcc) and Intel compiler (for host code)
module load CUDA/12.6.0
module load intel


export PROJECT_ROOT="${HOME}/swp-parallel-manycore"
cd "${PROJECT_ROOT}/tasks/kmeans"

# Proceed with build

export OMP_PROC_BIND=close
export OMP_PLACES=cores
export OMP_NUM_THREADS=${NTHREADS:-96}

# Show available compilers for debugging
echo "Available compilers:"
which icpx g++ nvcc 2>/dev/null || true
echo ""

# Build and run the large problem (100M points, 50K centroids, 100 iterations)
# Note: nvcc doesn't officially support Intel icpx, so we use g++ as host compiler
HOST_COMPILER=$(which g++) make run-large
