#!/bin/zsh
#SBATCH --job-name=ms_ablation
#SBATCH --output=ablation_%j.txt
#SBATCH --cpus-per-task=96
#SBATCH --time=00:10:00
#SBATCH --partition=c23ms

export OMP_NUM_THREADS=96
export OMP_PROC_BIND=TRUE
export OMP_PLACES=cores

SIZE=999999999

echo "--- 1. GCC Base ---"
./merge_v1_gcc_base.exe $SIZE
./merge_v1_gcc_base.exe $SIZE

echo "--- 2. GCC Branchless ---"
./merge_v2_gcc_branchless.exe $SIZE
./merge_v2_gcc_branchless.exe $SIZE

echo "--- 3. Intel Branchless ---"
./merge_v3_intel_branchless.exe $SIZE
./merge_v3_intel_branchless.exe $SIZE

echo "--- 4. Intel SIMD ---"
./merge_v4_intel_simd.exe $SIZE
./merge_v4_intel_simd.exe $SIZE

echo "--- 5. Intel Full (Huge Pages) ---"
./merge_v5_intel_full.exe $SIZE
./merge_v5_intel_full.exe $SIZE

