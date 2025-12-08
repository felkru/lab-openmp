# Experiment diary

## Todo List

- [x] Parallel divide with tasks + cutoff
  - [x] determine best cutoff using ternary search
  - [ ] seperate MsSequential and MsParrallel to avoid cutoff checks
- [x] Parallel merge via block binary search
  - [x] determine the best cutoff here
- [x] NUMA-local memory
- [x] Replace the single-threaded sorts after the cutoff with a more efficient algorithm
- [ ] Work-stealing / dynamic scheduling
- [x] Reset to 23 iterations
- [r] SIMD in merge kernels
- [ ] Cache-line aware output
- [ ] Pre-allocated temp buffer
- [ ] Profile & tune threshold

Goal: 0,5s for large run

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

_96 Cores, slurm job for run-large_

```zsh
done, took 0.191000 sec. Verification... successful.
```

_96 Cores, slurm job for run-large_

```zsh
done, took 11.134000 sec. Verification... successful.
```

### Tune task cutoff manually

#### Noisy first tests with `NTHREADS=8 make run-small`

| Cutoff | Time (sec) |
| ------ | ---------- |
| 1000   | 0.436      |
| 5000   | 0.382      |
| 10000  | 0.381      |
| 20000  | 0.378      |
| 50000  | 0.381      |

## Tests with `NTHREADS=8 make run-mid`

| Cutoff | Time (sec) |
| ------ | ---------- |
| 10000  | 4.621      |
| 20000  | 4.545      |
| 50000  | 5.228      |

_Result:_ Go with a cutoff of `20.000` for now.

## Parrallel merge via binary search

## Tuning Results

(From now on all tests have been performed using quick-test.sh (96 cores, large problem))

| Cutoff | Time (sec) |
| ------ | ---------- |
| 250000 | 2.974000   |
| 173333 | 2.984000   |
| 100000 | 3.140000   |
| 50000  | 3.272000   |

## Numa-local memory

```zsh
done, took 1.337000 sec. Verification... successful.
```

## Replace single-threaded merge-sorts (after cutoff) with std::sort

cutoff 30.000

```zsh
done, took 1.503000 sec. Verification... successful.
```

cutoff 5.000

```zsh
done, took 1.507000 sec. Verification... successful.
```

## Replace single-threaded merge-sorts with Radix Sort

```zsh
done, took  0.946 sec. Verification... successful.
```

## Branchless Merge + SIMD + Huge Pages

- **Changes**:
  - Branchless logic, removed `if/else`
  - Switched to Intel Compiler (`icpc`)
  - Added `#pragma ivdep` to the merge loop to enable vectorization.
  - `Huge Pages` using `posix_memalign` (2MB) and `madvise`.
- **Performance**:
  Job IDs: `62916635`, `62916636`, `62916745`.
  Output file: `tasks/merge-sort/experiments/results/ablation_results.txt`.

**Configurations Tested:**

1.  **GCC Base**: Original code (with trivial fixes), GCC compiler.
2.  **GCC Branchless**: Branchless merge, GCC.
3.  **Intel Branchless**: Branchless merge, Intel Compiler.
4.  **Intel SIMD**: Branchless + `#pragma ivdep`, Intel.
5.  **Intel Full**: Branchless + SIMD + Huge Pages.

**Results (Large Problem, 96 threads):**
| Configuration | Time (sec) | Notes |
| :--- | :--- | :--- |
| **1. GCC Base** | 0.936s | Baseline (optimized GCC) |
| **2. GCC Branchless** | 1.191s | Significant regression. Branchless logic hinders GCC. |
| **3. Intel Branchless** | **0.816s** | **Winner** |
| **4. Intel SIMD** | 0.828s | Slightly slower than v3. `ivdep` might be unnecessary or harmful. |
| **5. Intel Full (Huge Pages)** | 0.858s | Regression. Huge pages overhead > benefit? |

**Conclusion:**
The winning configuration is **Intel Compiler + Branchless Logic**, achieving **0.816s**.
Huge pages and explicit SIMD hints (ivdep) did not provide further benefit on this specific cluster/workload.
GCC performs significantly worse with the branchless implementation.
