# Software Lab: Parallel Programming for Many-Core Architectures with OpenMP

## Handouts

[![pipeline status](https://git-ce.rwth-aachen.de/hpc-lecture/lab-openmp/badges/master/pipeline.svg)](https://git-ce.rwth-aachen.de/hpc-lecture/lab-openmp/-/commits/master)

[Kmeans](https://git-ce.rwth-aachen.de/hpc-lecture/lab-openmp/-/jobs/artifacts/master/file/handouts/kmeans.tar.gz?job=handouts)

[Sobel](https://git-ce.rwth-aachen.de/hpc-lecture/lab-openmp/-/jobs/artifacts/master/file/handouts/sobel.tar.gz?job=handouts)

[Merge-sort](https://git-ce.rwth-aachen.de/hpc-lecture/lab-openmp/-/jobs/artifacts/master/file/handouts/merge-sort.tar.gz?job=handouts)

[spmxv](https://git-ce.rwth-aachen.de/hpc-lecture/lab-openmp/-/jobs/artifacts/master/file/handouts/spmxv.tar.gz?job=handouts)

[skeleton](https://git-ce.rwth-aachen.de/hpc-lecture/lab-openmp/-/jobs/artifacts/master/file/handouts/skeleton.tar.gz?job=handouts)

[Env scripts](https://git-ce.rwth-aachen.de/hpc-lecture/lab-openmp/-/jobs/artifacts/master/file/handouts/lab-openmp.tar.gz?job=handouts)


## TODOs

### Regularly every Year

- Setup thesis compute project
  - Apply for compute resources (and if desired for an advanced reservation which is available during in-person meetings)
  - Collect the students' user-ids on the cluster
  - Add all students to the compute project
- Setup Moodle room
  - Schedule automatic uploads of tar archives
  - Schedule automatic uploads of slides

### Once

- Add example of a good dev. diary
- Add improved reference solution for `kmeans` which:
  - initializes the device(s) before entering the time measurement
  - uses hybrid parallelism i.e. multi-threading on the CPU as well
  - supports multiple devices
- Check why `-O1` improves performance for `spmxv`

## Creating New Tasks

A template is provided in the `skeleton` task, which can also be used as a starting point for creating a new task.

### Adding a Reference Implementation

- create a directory under `tasks` using all lowercase letters, which uniquely identifies the new task
- directories for reference versions should use the naming scheme `XX_Name`, where `XX` are two digits and `Name` is a unique identifier in camelcase
- each newly created task should have two directories `00_Handout` and `01_Basic` which contain the handout version and a serial implementation of the task respectively

### Scripting Integration

- to allow for reuse of benchmarking scripts the following Makefile targets and conventions should be available:
  - `build`, which creates the task's main executable
  - `run-small`, which runs the task's main executable utilizing a pre-defined small problem size
  - `run-large`, which runs the task's main executable utilizing a pre-defined large problem size
  - `clean`, which removes all temporary build files from previous compilations
  - `archive`, which creates a tar archive of all files relevant for evaluation i.e. omit files which are shared between all groups
  - following a common style for passing the number of threads for a given execution, the environment variable `${NTHREADS}` should be read out to set `${OMP_NUM_THREADS}` accordingly
- integrating a new task into the `parse-benchmark.sh` script is possible by providing a custom result parser as described in [this section](#result-parsing-integration-of-new-tasks)
- integrating a new task into the `parse-competition.sh` script is possible by providing a custom prepare scripts as described in [this section](#competition-integration-of-new-tasks)

## Scripts

### Required Directory Hierarchy

```sh
$ tree .
.
├── .Rprofile
├── renv.lock
├── renv
├── ...
├── scripts
│   ├── benchmark
│   │   └── collect-benchmark.sh
│   ├── parse
│   │   ├── parse-benchmark.sh
│   │   └── result-parsers
│   └── visualize
│       ├── visualize-benchmark.R
│       └── visualize-comparison.R
└── tasks
    ├── merge-sort
    ├── ...
    └── spmxv
```

### Instructions for Dependency Installation

```sh
# this module has to be loaded before executing any Rscript in this repository
$ module load MATH r-project/4.0.2
$ R
> renv::init()
# press 1 to install the required libraries
```

### Overview

```sh
$ tree scripts
scripts
├── batch                               # directory for batch scripts which are templates for the students
│   ├── slurm.batch.gpu.sh              # --> standard execution on CPU backend nodes with GPUs
│   ├── slurm.batch.knl.sh              # --> standard execution on KNL backend nodes
│   ├── slurm.interactive.gpu.sh        # --> interactive session on CPU backend nodes with GPUs
│   └── slurm.interactive.knl.sh        # --> interactive session on KNL backend nodes
├── benchmark                           # directory for scripts related to benchmarking individual task versions
│   ├── collect-benchmark.sh            # --> main script to collect measurements with multiple thread counts
│   └── setup-environment.sh            # --> example script which can be sourced to setup a reproducible shell environment
├── competition                         # directory for scripts related to collecting measurements of multiple task versions (as done in the final student competition evaluation)
│   ├── collect-competition.sh          # --> main script to collect measurements for one fixed execution configuration
│   └── prepare/*                       # --> per-task scripts to create any task specific files before data collection
├── housekeeping                        # directory for scripts that help manage the software lab
│   ├── make-handout-base.sh            # --> script to create a tar archive containing the base directory structure which can be distributed to students
│   ├── make-handout-task.sh            # --> script to create tar archives of individual tasks which can be distributed to students
│   └── create-reference-competition.sh # --> script to create tar archives for the reference implementations of a task
├── parse                               # directory for scripts related to parsing collected measurements into a csv format
│   ├── parse-benchmark.sh              # --> main script to summarize an individual benchmark measurement
│   ├── parse-competition.sh            # --> main script to summarize a competition measurement
│   └── result-parsers/*                # --> per-task scripts to parse the task output into a csv format
└── visualize                           # directory for scripts related to visualizing measurements from csv results
    ├── visualize-benchmark.R           # --> script to inspect an individual benchmark measurement
    ├── visualize-comparison.R          # --> script to compare multiple benchmark measurements between each other
    └── visualize-competition.R         # --> script to evaluate a competition measurement
```

### Result Parsing Integration of new Tasks

The generic implementation of the `parse-benchmark.sh` script utilizes scripts under `result-parsers` to extract task specific fields from result files.
Integrating with this process without modifying the source of `parse-benchmark.sh` directly is possible by following these steps:

- create a shell script under `result-parsers` using `${task}.sh` as the script name
- the provided shell script needs to output the task specific csv header fields, when no input file is given (`[ ${#} -eq 0 ]`)
- otherwise the shell script needs to parse the provided input file and output the extracted performance metrics using a csv style

An example is provided as `skeleton.sh`, which can also be used as a starting point for writing your own result parser.

### Competition Integration of new Tasks

The generic implementation of the `collect-competition.sh` script utilizes scripts under `prepare` to prepare task directories considering task specific files.
Integrating with this process without modifying the source of `collect-competition.sh` directly is possible by following these steps:

- create a shell script under `prepare` using `${task}.sh` as the script name
- the shell script needs to create / copy all task specific files, which are not part of the extracted archive, in / into the given directory provided as script argument `${1}`

An example is provided as `skeleton.sh`, which can also be used as a starting point for writing your own prepare script.
