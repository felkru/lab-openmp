# Experiment diary

## Todo List

- [x] Convert to GPU code
- [x] Remove sqrt inside the loop
- [ ] Use double2 (16-byte aligned) loads
- [ ] Rely on L2 Cache for centroids (K=50k)
- [ ] Triangle Inequality (Elkan's)
- [ ] Keep points on GPU; Async transfers

| Optimization | Method                                  | Impact                       |
| ------------ | --------------------------------------- | ---------------------------- |
| Compute      | Remove sqrt inside the loop.            | High (Arithmetic throughput) |
| Memory       | Use double2 (16-byte aligned) loads.    | High (Bandwidth efficiency)  |
| Memory       | Rely on L2 Cache for centroids (K=50k). | Critical (H100 specific)     |
| Algorithm    | Triangle Inequality (Elkan's).          | SOTA (Reduces complexity)    |
| Pipeline     | Keep points on GPU; Async transfers.    | Medium (Reduces latency)     |

## Benchmarks

| Device | Dataset | Iterations | Threads | Time (s) | Notes                       |
| :----- | :------ | :--------- | :------ | :------- | :-------------------------- |
| CPU    | small   | 20         | 1       | 0.000662 | Baseline (g++ -O3)          |
| GPU    | small   | 20         | 1       | 0.012394 | Global Atomics (Login Node) |
| GPU    | mid     | 50         | 1       | 0.210154 | Global Atomics (Login Node) |
