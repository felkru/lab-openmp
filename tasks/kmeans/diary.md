# Experiment diary

## Todo List

- [x] Convert to GPU code
- [x] Remove sqrt inside the loop
- [x] Use struct for 16-byte aligned loads - no improvement, removed to prevent unnecessary complexity§
- [ ] Triangle Inequality (Elkan's)
- [ ] Keep points on GPU; Async transfers
- [ ] Add support for 4 gpus

## Benchmarks

| Device | Dataset | Iterations | Threads | Time (s) | Notes                                       |
| :----- | :------ | :--------- | :------ | :------- | :------------------------------------------ |
| CPU    | small   | 20         | 1       | 0.000662 | Baseline (g++ -O3)                          |
| GPU    | small   | 20         | 1       | 0.012394 | Global Atomics (Login Node)                 |
| GPU    | mid     | 50         | 1       | 0.210154 | Global Atomics (Login Node)                 |
| GPU    | mid     | 50         | 1       | 0.217191 | struct loads                                |
| GPU    | mid     | 50         | 1       | 0.318229 | + Triangle Inequality (Regressed, Reverted) |
