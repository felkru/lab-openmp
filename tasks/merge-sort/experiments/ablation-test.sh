#!/bin/bash

# Navigate to task directory
cd tasks/merge-sort || exit 1

# Load environment
source ./setup-environment.sh

# Common flags
FLAGS="-O3 -march=native -fopenmp"

echo "Compiling variants..."

# 1. GCC Base (Branch-ful, No Huge Pages)
CXX=g++
echo "Compiling v1_gcc_base..."
$CXX $FLAGS -o merge_v1_gcc_base.exe main.cpp

# 2. GCC Branchless
echo "Compiling v2_gcc_branchless..."
$CXX $FLAGS -DENABLE_BRANCHLESS -o merge_v2_gcc_branchless.exe main.cpp

# Switch to Intel
CXX=icpx
FLAGS_INTEL="-O3 -xHost -qopenmp -Wno-deprecated-declarations"

# 3. Intel Branchless (No SIMD pragma yet, No Huge Pages)
echo "Compiling v3_intel_branchless..."
$CXX $FLAGS_INTEL -DENABLE_BRANCHLESS -o merge_v3_intel_branchless.exe main.cpp

# 4. Intel + SIMD (ivdep)
echo "Compiling v4_intel_simd..."
$CXX $FLAGS_INTEL -DENABLE_BRANCHLESS -DENABLE_IVDEP -o merge_v4_intel_simd.exe main.cpp

# 5. Intel + SIMD + Huge Pages (Full)
echo "Compiling v5_intel_full..."
$CXX $FLAGS_INTEL -DENABLE_BRANCHLESS -DENABLE_IVDEP -DENABLE_HUGE_PAGES -o merge_v5_intel_full.exe main.cpp

echo "Submitting job..."

# Create job script
cat <<EOF > ablation_job.sh
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
./merge_v1_gcc_base.exe \$SIZE
./merge_v1_gcc_base.exe \$SIZE

echo "--- 2. GCC Branchless ---"
./merge_v2_gcc_branchless.exe \$SIZE
./merge_v2_gcc_branchless.exe \$SIZE

echo "--- 3. Intel Branchless ---"
./merge_v3_intel_branchless.exe \$SIZE
./merge_v3_intel_branchless.exe \$SIZE

echo "--- 4. Intel SIMD ---"
./merge_v4_intel_simd.exe \$SIZE
./merge_v4_intel_simd.exe \$SIZE

echo "--- 5. Intel Full (Huge Pages) ---"
./merge_v5_intel_full.exe \$SIZE
./merge_v5_intel_full.exe \$SIZE

EOF

sbatch ablation_job.sh
