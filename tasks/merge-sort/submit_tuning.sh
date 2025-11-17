#!/usr/bin/env zsh
#SBATCH --job-name=tune_cutoff
#SBATCH --account=lect0163
#SBATCH --output=tuning_%j.txt
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=96
#SBATCH --exclusive

cd ~/lab-openmp/tasks/merge-sort
source setup-environment.sh
python tune_cutoff.py