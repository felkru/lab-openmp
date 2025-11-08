#!/usr/bin/env zsh

### Job name
#SBATCH --job-name=SWP_ManyCore_OpenMP
#SBATCH --account=<project-id>
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
#SBATCH --gres=gpu:4

### wait for dispatch
sleep 7200
### execute 'ssh -Y <allocated-node>' from another shell window
### to get X11 forwarding and execute commands interactively
### when you are finished use 'scancel <job-id>' to free the resources
