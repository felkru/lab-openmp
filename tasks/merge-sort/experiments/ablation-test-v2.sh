#!/bin/bash

# Navigate to task directory
cd /home/ey626511/lab-openmp/tasks/merge-sort || exit 1

# Binaries should arguably be ready from previous run, but let's check
if [ ! -f merge_v1_gcc_base.exe ]; then
    echo "Binaries missing, please run ablation-test.sh key part first or recompile."
    # Recompile v1 just in case
    source ./setup-environment.sh
    CXX=g++
    FLAGS="-O3 -march=native -fopenmp"
    $CXX $FLAGS -o merge_v1_gcc_base.exe main.cpp
    $CXX $FLAGS -DENABLE_BRANCHLESS -o merge_v2_gcc_branchless.exe main.cpp
    
    CXX=icpx
    FLAGS_INTEL="-O3 -xHost -qopenmp -Wno-deprecated-declarations"
    $CXX $FLAGS_INTEL -DENABLE_BRANCHLESS -o merge_v3_intel_branchless.exe main.cpp
    $CXX $FLAGS_INTEL -DENABLE_BRANCHLESS -DENABLE_IVDEP -o merge_v4_intel_simd.exe main.cpp
    $CXX $FLAGS_INTEL -DENABLE_BRANCHLESS -DENABLE_IVDEP -DENABLE_HUGE_PAGES -o merge_v5_intel_full.exe main.cpp
fi

# Create job script
cat <<EOF > ablation_job_v2.sh
#!/bin/zsh
#SBATCH --job-name=ms_ablation_v2
#SBATCH --output=/home/ey626511/lab-openmp/tasks/merge-sort/ablation_results.txt
#SBATCH --cpus-per-task=96
#SBATCH --time=00:10:00
#SBATCH --partition=c23ms

export OMP_NUM_THREADS=96
export OMP_PROC_BIND=TRUE
export OMP_PLACES=cores

SIZE=999999999

echo "--- 1. GCC Base ---"
./merge_v1_gcc_base.exe \$SIZE

echo "--- 2. GCC Branchless ---"
./merge_v2_gcc_branchless.exe \$SIZE

echo "--- 3. Intel Branchless ---"
./merge_v3_intel_branchless.exe \$SIZE

echo "--- 4. Intel SIMD ---"
./merge_v4_intel_simd.exe \$SIZE

echo "--- 5. Intel Full (Huge Pages) ---"
./merge_v5_intel_full.exe \$SIZE

EOF

sbatch ablation_job_v2.sh
