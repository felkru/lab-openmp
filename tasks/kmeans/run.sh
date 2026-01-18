#!/usr/bin/env zsh

#SBATCH --job-name=k-run
#SBATCH --account=lect0163
#SBATCH --output=benchmark_output_%j.log
#SBATCH --error=benchmark_error_%j.log
#SBATCH --time=09:00:00
#SBATCH --mem=0
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --gres=gpu:4

export TMPDIR="${HOME}/tmp"
mkdir -p "${TMPDIR}"

export PROJECT_ROOT="${HOME}/swp-parallel-manycore"
cd "${PROJECT_ROOT}/tasks/kmeans"

export OMP_PROC_BIND=close
export OMP_PLACES=cores
export OMP_NUM_THREADS=${NTHREADS:-96}

NUM_EXECUTIONS=${NUM_EXECUTIONS:-10}

echo "CUDA VERSION (nvcc)"

module purge
module load CUDA/12.6.0
module load intel

echo "Using compilers:"
which g++ nvcc 2>/dev/null || true
echo ""

echo "=== Verification: Comparing CPU vs CUDA (exact Lloyd's mode) ==="

# IMPORTANT: Must use < 250K points so CUDA uses exact Lloyd's (not mini-batch)
# Otherwise CPU (exact) and CUDA (mini-batch) produce different results by design
# TOTAL_BATCH_SIZE in main.cu = 250000
VERIFY_POINTS=200000
VERIFY_CENTROIDS=500
VERIFY_DIM=100
VERIFY_ITERS=5

# Generate verification input if it doesn't exist
if [ ! -f input/verify.in ]; then
    echo "Generating verification input..."
    module load Python
    python input/gen_input.py --file input/verify.in --k ${VERIFY_CENTROIDS} --n ${VERIFY_POINTS} --dim_x ${VERIFY_DIM} --dim_y ${VERIFY_DIM}
fi

make clean
make -f Makefile_omp cpu
./kmeans_cpu.exe input/verify.in ${VERIFY_DIM} ${VERIFY_POINTS} ${VERIFY_CENTROIDS} ${VERIFY_ITERS}
cp memory.out memory_cpu_verify.out

make clean
HOST_COMPILER=$(which g++) make release
./kmeans.exe input/verify.in ${VERIFY_DIM} ${VERIFY_POINTS} ${VERIFY_CENTROIDS} ${VERIFY_ITERS}
cp memory.out memory_cuda_verify.out

if ./utils/check_diff.py memory_cpu_verify.out memory_cuda_verify.out; then
    echo "VERIFICATION PASSED: CPU and CUDA outputs match within tolerance (1e-2)"
    echo "  (${VERIFY_POINTS} points, ${VERIFY_CENTROIDS} centroids, ${VERIFY_ITERS} iterations - exact Lloyd's mode)"
    rm -f memory_cpu_verify.out memory_cuda_verify.out
else
    echo "VERIFICATION FAILED: CPU and CUDA outputs differ significantly!"
    echo "Differences (Head):"
    diff memory_cpu_verify.out memory_cuda_verify.out | head -20
    echo ""
    echo "Aborting benchmark. Verification failed."
    exit 1
fi
echo ""

HOST_COMPILER=$(which g++) make run-large

echo "=== Running Benchmark via collect-benchmark.sh ==="
NUM_BENCHMARK_RUNS=${NUM_BENCHMARK_RUNS:-10}
VERSION="cuda-3gpu"

${PROJECT_ROOT}/scripts/benchmark/collect-benchmark.sh -t kmeans -v ${VERSION} -n ${NUM_BENCHMARK_RUNS}

BENCHMARK_DIR=$(ls -td ${PROJECT_ROOT}/benchmarking/kmeans/*-${VERSION} 2>/dev/null | head -1)

if [ -n "${BENCHMARK_DIR}" ]; then
    echo ""
    echo "=== Parsing Results ==="
    ${PROJECT_ROOT}/scripts/parse/parse-benchmark.sh -t kmeans -d "${BENCHMARK_DIR}" -n ${NUM_BENCHMARK_RUNS}
    
    if [ -f "${BENCHMARK_DIR}/benchmark.csv" ]; then
        echo "Results saved to: ${BENCHMARK_DIR}/benchmark.csv"
        cat "${BENCHMARK_DIR}/benchmark.csv"
        
        echo ""
        echo "=== Visualization ==="
        python3 ${PROJECT_ROOT}/scripts/visualize/visualize-benchmark.py \
            -csv "${BENCHMARK_DIR}/benchmark.csv" \
            -col seconds \
            -m "Time (seconds)" \
            -o "${BENCHMARK_DIR}/plot.png" \
            --no-ideal 2>/dev/null || echo "Visualization skipped (may need polars)"
        
        if [ -f "${BENCHMARK_DIR}/plot.png" ]; then
            echo "Plot saved to: ${BENCHMARK_DIR}/plot.png"
        fi
    fi
fi

echo ""
echo "=== All Done ==="
