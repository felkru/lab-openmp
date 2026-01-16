# Experiment diary

## Todo List

- [ ] Convert to GPU code
- [ ] Remove sqrt inside the loop
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
