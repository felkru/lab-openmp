#!/usr/bin/env zsh

### Job name
#SBATCH --job-name=Kmeans_GPU
#SBATCH --account=lect0163

### File / path where STDOUT will be written, the %j is the job id
#SBATCH --output=kmeans_gpu_%j.txt

### Request time
#SBATCH --time=00:10:00

### Set Queue
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --partition=c23g
#SBATCH --gres=gpu:1
#SBATCH --exclusive

# Set this to the correct path
TASK_DIR=~/lab-openmp/tasks/kmeans

echo "[$(date +'%H:%M:%S')] Starting Batch Job"

cd "${TASK_DIR}"
module purge
module load GCCcore/14.2.0 LLVM/20.1.7 CUDA/12.6.3

echo "[$(date +'%H:%M:%S')] Building..."
make clean release

echo "[$(date +'%H:%M:%S')] Running small test..."
# Default usage: small problem, 1 iteration
make run-small

echo "[$(date +'%H:%M:%S')] Job Complete"
