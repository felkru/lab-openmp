# Getting started

## Large Benchmark

1. Run `sbatch ./scripts/batch/slurm.batch.gpu.sh` to collect benchmarks on 96 cores async. 
*Note:* the .gpu.sh name is confusing, but doesn't mean it's using the GPU, but only that I adapted that file based on Tobias tips.

Current ETA is ~30min. with 6 iterations. The results will be stored in ./benchmarking/merge-sort/...

2. Run `zsh 
./scripts/parse/parse-benchmark.sh -d ./benchmarking/merge-sort/{datestring}-openmp
`, ensure benchmark.csv shows up on the top level of the folder you specified

3. Run to visualize your results:
```zsh
module load Python

python -m venv ./scritsp/visualize/venv

source ./scripts/visualize/venv/bin/activate

./scripts/visualize/visualize-benchmark.py -csv ./benchmarking/merge-sort/2025-11-16T10h53m12s-openmp/benchmark.csv -col seconds -m Seconds -d
```

