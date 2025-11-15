#!/usr/bin/env zsh

### Job name
#SBATCH --job-name=SWP_ManyCore_OpenMP
#SBATCH --account=lect0163
###SBATCH --reservation=<advanced-reservation-id>

### File / path where STDOUT will be written, the %j is the job id
#SBATCH --output=output_%j.txt

### Optional: Send mail when job has finished
###SBATCH --mail-type=END
###SBATCH --mail-user=<email-address>

### Request time
#SBATCH --time=01:00:00

### Set Queue
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=96
#SBATCH --exclusive
# #SBATCH --gres=gpu:4

# Set this to the correct path
BASE_DIR=~/lab-openmp
TASK=merge-sort

# name the benchmark folder
VERSION=openmp

cd "${BASE_DIR}"
./scripts/benchmark/collect-benchmark.sh --task "${TASK}" --version "${VERSION}"
