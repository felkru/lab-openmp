# Experiment diary

## Todo List
- [x] Parallel divide with tasks + cutoff
    - [ ] determine best cutoff using binary search
    - [ ] seperate MsSequential and MsParrallel to avoid cutoff checks 
- [ ] Parallel merge via block binary search
- [ ] SIMD in merge kernels
- [ ] Work-stealing / dynamic scheduling
- [ ] Cache-line aware output
- [ ] NUMA-local memory
- [ ] Pre-allocated temp buffer
- [ ] Profile & tune threshold
- [ ] Reset to 23 iterations

### Tools for profiling
perf, vtune, gprof, TAU

## Unmodified Code
```zsh
NTHREADS=8 make run-small
...
done, took 1.076000, 1.115000, 1.094000 sec. Verification... successful.
```

```zsh
NTHREADS=8 make run-mid
...
done, took 12.460000, 12.465000, 12.650000 sec. Verification... successful.
```

## Parallel divide with tasks + cutoff

```zsh
NTHREADS=8 make run-small

done, took 0.385000, 0.384000, 0.383000 sec. Verification... successful.
```

```zsh
NTHREADS=8 make run-mid

done, took 4.786000 sec. Verification... successful.
```

```zsh
NTHREADS=8 make run-large

done, took 52.269000 sec. Verification... successful.
```

*96 Cores, slurm job for run-large*
```zsh
done, took 0.191000 sec. Verification... successful.
```

*96 Cores, slurm job for run-large*
```zsh
done, took 11.134000 sec. Verification... successful.
```

### Tune task cutoff manually

#### Noisy first tests with `NTHREADS=8 make run-small`
| Cutoff | Time (sec) |
|--------|------------|
| 1000   | 0.436      |
| 5000   | 0.382      |
| 10000  | 0.381      |
| 20000  | 0.378      |
| 50000  | 0.381      |

## Tests with `NTHREADS=8 make run-mid`
| Cutoff | Time (sec) |
|--------|------------|
| 10000  | 4.621      |
| 20000  | 4.545      |
| 50000  | 5.228      |

*Result:* Go with a cutoff of `20.000` for now.

