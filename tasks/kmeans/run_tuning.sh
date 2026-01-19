#!/bin/bash
# tuning.sh

# Load modules
module load GCCcore/14.2.0 LLVM/20.1.7 CUDA/12.6.3

# Compile first (assumes done, but good measure)
# make release CXX=clang++

export CUDA_VISIBLE_DEVICES=1

INPUT="input/mid.in"
# Check if input exists, else use absolute path or generate
if [ ! -f "$INPUT" ]; then
    INPUT="../input/mid.in"
fi

echo "Running Tuning Benchmark on Device 1"
echo "Dataset: $INPUT"
echo "| Cutoff | Time (s) |"
echo "|--------|----------|"

for cutoff in 0 1 5 10 20 50; do
    # Run with OMP_NUM_THREADS=1 (GPU offloading doesn't depend on host threads usually)
    # Output format: "Time Elapsed: X.XXXXXX s"
    OUTPUT=$(OMP_NUM_THREADS=1 ./kmeans.exe $INPUT 100 1000000 5000 50 $cutoff)
    TIME=$(echo "$OUTPUT" | grep "Time Elapsed" | awk '{print $3}')
    echo "| $cutoff | $TIME |"
done
