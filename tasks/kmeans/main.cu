#include <algorithm>
#include <cfloat>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cublas_v2.h>
#include <cuda_runtime.h>
#include <fstream>
#include <iostream>
#include <omp.h>
#include <string>
#include <sys/time.h>
#include <vector>

#define DEFAULT_K 5
#define DEFAULT_NITERS 20
#define TOTAL_BATCH_SIZE 250000
#define TILE_SIZE 2048 // Tile size for cuBLAS GEMM

#define ENABLE_MINI_BATCH false

double get_time() {
  struct timeval tv;
  gettimeofday(&tv, (struct timezone *)0);
  return ((double)tv.tv_sec + (double)tv.tv_usec / 1000000.0);
}

void read_points(std::string filename, double *px, double *py, int n) {
  std::ifstream infile{filename};
  double x, y;
  int i = 0;
  while (infile >> x >> y) {
    if (i >= n) {
      printf("WARNING: more points in input file '%s' than read: stopping "
             "after %d lines\n",
             filename.c_str(), i);
      return;
    }
    px[i] = x;
    py[i] = y;
    i++;
  }
}

// Helper to check if K fits in shared memory (Max 48KB usually, safe bet 32KB)
// K * (sizeof(double)*2 + sizeof(int)) = K * 20 bytes.
// 32000 / 20 = 1600.
bool fits_in_shared(int k) {
  return (k * (sizeof(double) * 2 + sizeof(int))) < (32 * 1024);
}

void write_memory(std::string filename, int niters, double *memory_x,
                  double *memory_y, int k) {
  std::ofstream outfile{filename};
  for (int iter = 0; iter < niters + 1; ++iter) {
    for (int i = 0; i < k; ++i) {
      outfile << iter << ' ' << memory_x[iter * k + i] << ' '
              << memory_y[iter * k + i] << '\n';
    }
  }
}

void init_centroids(double *centroids_x, double *centroids_y, int k, int d) {
  for (int i = 0; i < k; ++i) {
    centroids_x[i] = rand() % d;
    centroids_y[i] = rand() % d;
  }
}

// Compute ||c||^2 for all centroids
__global__ void compute_centroid_norms(int k,
                                       const double *__restrict__ centroids_x,
                                       const double *__restrict__ centroids_y,
                                       double *__restrict__ norms) {
  int idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < k) {
    double cx = centroids_x[idx];
    double cy = centroids_y[idx];
    norms[idx] = cx * cx + cy * cy;
  }
}

// Find nearest centroid using precomputed distance matrix (from GEMM)
// dist_matrix contains -2 * x . c
// We calculate full_dist = dist_matrix + ||c||^2 (ignoring ||x||^2 as it's
// constant for argmin)
__global__ void find_nearest_centroid_gemm(
    int batch_size,                         // Number of points in this tile
    int k,                                  // Number of centroids
    const double *__restrict__ dist_matrix, // [batch_size x k] (Column Major)
    const double *__restrict__ c_norms,     // [k]
    const double
        *__restrict__ points_x, // [batch_size] (Actual x values for summing)
    const double
        *__restrict__ points_y, // [batch_size] (Actual y values for summing)
    double *sum_x, double *sum_y, int *count) {

  int idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < batch_size) {
    double min_dist = DBL_MAX;
    int best_centroid = 0;

    // dist_matrix is column-major: batch_size rows, k cols
    // Element (idx, j) is at dist_matrix[idx + j * batch_size]

    for (int j = 0; j < k; ++j) {
      double dist = dist_matrix[idx + j * batch_size] + c_norms[j];
      if (dist < min_dist) {
        min_dist = dist;
        best_centroid = j;
      }
    }

    // Atomic updates
    atomicAdd(&sum_x[best_centroid], points_x[idx]);
    atomicAdd(&sum_y[best_centroid], points_y[idx]);
    atomicAdd(&count[best_centroid], 1);
  }
}

#define NUM_STREAMS 4

// Shared memory version of find_nearest_centroid_gemm
// optimization 1: reducing the number of atomic add steps by summing in
// parrallel first using local memory
extern __shared__ char smem[];
__global__ void find_nearest_centroid_gemm_shared(
    int batch_size,                         // Number of points in this tile
    int k,                                  // Number of centroids
    const double *__restrict__ dist_matrix, // [batch_size x k]
    const double *__restrict__ c_norms,     // [k]
    const double *__restrict__ points_x,    // [batch_size]
    const double *__restrict__ points_y,    // [batch_size]
    double *sum_x, double *sum_y, int *count) {

  double *s_sum_x = (double *)smem;
  double *s_sum_y = (double *)&s_sum_x[k];
  int *s_count = (int *)&s_sum_y[k];

  // Initialize shared memory
  for (int i = threadIdx.x; i < k; i += blockDim.x) {
    s_sum_x[i] = 0.0;
    s_sum_y[i] = 0.0;
    s_count[i] = 0;
  }
  __syncthreads();

  int idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < batch_size) {
    double min_dist = DBL_MAX;
    int best_centroid = 0;

    for (int j = 0; j < k; ++j) {
      double dist = dist_matrix[idx + j * batch_size] + c_norms[j];
      if (dist < min_dist) {
        min_dist = dist;
        best_centroid = j;
      }
    }

    // Atomic updates to Shared Memory
    atomicAdd(&s_sum_x[best_centroid], points_x[idx]);
    atomicAdd(&s_sum_y[best_centroid], points_y[idx]);
    atomicAdd(&s_count[best_centroid], 1);
  }

  __syncthreads();

  // Write back to Global Memory (Partial Sums for this stream)
  for (int i = threadIdx.x; i < k; i += blockDim.x) {
    if (s_count[i] > 0) {
      atomicAdd(&sum_x[i], s_sum_x[i]);
      atomicAdd(&sum_y[i], s_sum_y[i]);
      atomicAdd(&count[i], s_count[i]);
    }
  }
}

// Reduce partial sums from streams into main buffer
__global__ void reduce_partial_sums(int k, int num_streams,
                                    double **partial_sum_x,
                                    double **partial_sum_y, int **partial_count,
                                    double *final_sum_x, double *final_sum_y,
                                    int *final_count) {
  int idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < k) {
    double sx = 0.0;
    double sy = 0.0;
    int c = 0;
    for (int s = 0; s < num_streams; ++s) {
      sx += partial_sum_x[s][idx];
      sy += partial_sum_y[s][idx];
      c += partial_count[s][idx];
    }
    final_sum_x[idx] = sx;
    final_sum_y[idx] = sy;
    final_count[idx] = c;
  }
}

// Update centroid positions (Reduction on GPU 0)
// Aggregates partial sums from all 3 GPUs
__global__ void update_centroid_positions(int k, int num_devices,
                                          double **all_sum_x,
                                          double **all_sum_y, int **all_count,
                                          double *centroids_x,
                                          double *centroids_y) {
  int j = blockIdx.x * blockDim.x + threadIdx.x;
  if (j >= k)
    return;

  int total_c = 0;
  double total_sx = 0.0;
  double total_sy = 0.0;

  for (int d = 0; d < num_devices; ++d) {
    total_c += all_count[d][j];
    total_sx += all_sum_x[d][j];
    total_sy += all_sum_y[d][j];
  }

  if (total_c > 0) {
    centroids_x[j] = total_sx / total_c;
    centroids_y[j] = total_sy / total_c;
  }
}

// ---------------- DEVICE DATA STRUCT ----------------
struct DeviceData {
  int id;
  int point_count; // total points / num_devices
  double *points_x, *points_y;
  double *centroids_x, *centroids_y;
  double *sum_x, *sum_y;
  int *count;

  // Per-stream resources
  cudaStream_t streams[NUM_STREAMS];
  cublasHandle_t handles[NUM_STREAMS];
  double *d_dist[NUM_STREAMS];

  // Partial sums for streams to avoid atomic contention
  double *p_sum_x[NUM_STREAMS];
  double *p_sum_y[NUM_STREAMS];
  int *p_count[NUM_STREAMS];

  double *d_c_norms; // Shared across streams (read-only)
};

int main(int argc, const char *argv[]) {
  srand(1234);
  if (argc < 4 || argc > 6) {
    printf("Usage: %s <input file> <size dimensions> <num points> <num "
           "centroids> <num iters>\n",
           argv[0]);
    return EXIT_FAILURE;
  }

  const int dim = atoi(argv[2]);                        // number of dimensions
  const char *input_file = argv[1];                     // input file
  const int n = atoi(argv[3]);                          // number of points
  const int k = (argc > 4 ? atoi(argv[4]) : DEFAULT_K); // number of centroids
  const int niters =
      (argc > 5 ? atoi(argv[5]) : DEFAULT_NITERS); // number of iterations

  // Initilise and load Host Data Points and Centroids in SOA (Struct of Arrays)
  // [x0, y0, x1, y1, x2, y2, ...] -> [x0, x1, x2, ...] AND [y0, y1, y2, ...]
  std::vector<double> host_points_x(n), host_points_y(n);
  std::vector<double> host_centroids_x(k), host_centroids_y(k);

  read_points(input_file, host_points_x.data(), host_points_y.data(), n);
  init_centroids(host_centroids_x.data(), host_centroids_y.data(), k, dim);

  std::vector<double> host_memory_x((niters + 1) * k),
      host_memory_y((niters + 1) * k);
  for (int j = 0; j < k; ++j) {
    host_memory_x[j] = host_centroids_x[j];
    host_memory_y[j] = host_centroids_y[j];
  }

  // would now directly start the computation on cpu.
  // but for gpu usage need to distribute data onto the gpus
  // use cuda calls instead of openmp for that

  int num_devices = 0;
  cudaGetDeviceCount(&num_devices);
  if (num_devices == 0) {
    fprintf(stderr, "No CUDA devices found!\n");
    return EXIT_FAILURE;
  }

  const char *env_p = std::getenv("OMP_NUM_THREADS");
  if (env_p) {
    int env_n = std::atoi(env_p);
    if (env_n > 0 && env_n < num_devices) {
      num_devices = env_n;
    }
  }

  // 1 OpenMP Thread = 1 GPU
  omp_set_num_threads(num_devices);
  std::vector<DeviceData> devices(num_devices);
  int points_per_gpu = (n + num_devices - 1) /
                       num_devices; // divide points evenly accross all gpus

  // cudaMallocHost nessesary for the use of streams and memcpy
  double *pinned_x, *pinned_y;
  cudaMallocHost(&pinned_x, n * sizeof(double));
  cudaMallocHost(&pinned_y, n * sizeof(double));
  // Direct copy of data to pinned memory on the CPU
  // GPU DMA can directly access pinned memory
  memcpy(pinned_x, host_points_x.data(), n * sizeof(double));
  memcpy(pinned_y, host_points_y.data(), n * sizeof(double));

// Allocation Phase:  Alloc and Copy Points to each GPU
#pragma omp parallel num_threads(num_devices)
  {
    int d = omp_get_thread_num();
    cudaSetDevice(d);
    // Initialize specific device and streams
    devices[d].id = d;
    for (int s = 0; s < NUM_STREAMS; ++s) {
      cudaStreamCreate(&devices[d].streams[s]);
      cublasCreate(&devices[d].handles[s]);
      cublasSetStream(devices[d].handles[s], devices[d].streams[s]);

      cudaMalloc(&devices[d].d_dist[s], TILE_SIZE * k * sizeof(double));

      cudaMalloc(&devices[d].p_sum_x[s], k * sizeof(double));
      cudaMalloc(&devices[d].p_sum_y[s], k * sizeof(double));
      cudaMalloc(&devices[d].p_count[s], k * sizeof(int));
    }

    int start = d * points_per_gpu;
    int end = std::min(start + points_per_gpu, n);
    devices[d].point_count = end - start;

    // Allocate space for points
    cudaMalloc(&devices[d].points_x, devices[d].point_count * sizeof(double));
    cudaMalloc(&devices[d].points_y, devices[d].point_count * sizeof(double));

    // Copy points from cpu to gpu
    cudaMemcpyAsync(devices[d].points_x, pinned_x + start,
                    devices[d].point_count * sizeof(double),
                    cudaMemcpyHostToDevice, devices[d].streams[0]);
    cudaMemcpyAsync(devices[d].points_y, pinned_y + start,
                    devices[d].point_count * sizeof(double),
                    cudaMemcpyHostToDevice, devices[d].streams[0]);

    // Allocate space for centroids, sums, and counts Aux
    cudaMalloc(&devices[d].centroids_x, k * sizeof(double));
    cudaMalloc(&devices[d].centroids_y, k * sizeof(double));
    cudaMalloc(&devices[d].sum_x, k * sizeof(double));
    cudaMalloc(&devices[d].sum_y, k * sizeof(double));
    cudaMalloc(&devices[d].count, k * sizeof(int));

    // Copy initial centroids using Stream 0
    cudaMemcpyAsync(devices[d].centroids_x, host_centroids_x.data(),
                    k * sizeof(double), cudaMemcpyHostToDevice,
                    devices[d].streams[0]);
    cudaMemcpyAsync(devices[d].centroids_y, host_centroids_y.data(),
                    k * sizeof(double), cudaMemcpyHostToDevice,
                    devices[d].streams[0]);

    // Scratch buffer for norms
    cudaMalloc(&devices[d].d_c_norms, k * sizeof(double));

    cudaStreamSynchronize(devices[d].streams[0]);

// Enable P2P
#pragma omp barrier
    for (int peer = 0; peer < num_devices; ++peer) {
      if (d != peer) {
        // Enable GPU to GPU Transfer via NVLink
        cudaDeviceEnablePeerAccess(peer, 0);
      }
    }
#pragma omp barrier
  }

  // Alloc gather buffers on GPU 0 for reduction across all GPUs
  // Also need to store the count since we need to average the points.
  // And different GPUs can have different number of points and so also
  // different number of count values. For the computation new_centroid_x =
  // total_sum_x / total_count new_centroid_y = total_sum_y / total_count
  cudaSetDevice(0);
  double **d_gather_sum_x, **d_gather_sum_y;
  int **d_gather_count;

  std::vector<double *> h_gather_sum_x(num_devices),
      h_gather_sum_y(num_devices);
  std::vector<int *> h_gather_count(num_devices);

  // Allocate Acual Data for the results of each GPU on GPU 0
  for (int d = 0; d < num_devices; ++d) {
    h_gather_sum_x[d] = devices[d].sum_x;
    h_gather_sum_y[d] = devices[d].sum_y;
    h_gather_count[d] = devices[d].count;
  }

  // Allocate Pointers for the Data for each GPU on GPU 0
  cudaMalloc(&d_gather_sum_x, num_devices * sizeof(double *));
  cudaMalloc(&d_gather_sum_y, num_devices * sizeof(double *));
  cudaMalloc(&d_gather_count, num_devices * sizeof(int *));
  // Copy these Pointers from CPU to GPU 0
  cudaMemcpy(d_gather_sum_x, h_gather_sum_x.data(),
             num_devices * sizeof(double *), cudaMemcpyHostToDevice);
  cudaMemcpy(d_gather_sum_y, h_gather_sum_y.data(),
             num_devices * sizeof(double *), cudaMemcpyHostToDevice);
  cudaMemcpy(d_gather_count, h_gather_count.data(), num_devices * sizeof(int *),
             cudaMemcpyHostToDevice);

  const char *mode =
      (ENABLE_MINI_BATCH && n >= TOTAL_BATCH_SIZE) ? "Mini-Batch" : "Exact";
  printf("Executing k-means à %d iterations (%s mode, %d GPUs)...\n", niters,
         mode, num_devices);
  double runtime = get_time();

  // Pre-allocate array for random offsets (rand() is not thread-safe)
  std::vector<int> random_offsets(num_devices);

  // Compute Phase:
  for (int iter = 0; iter < niters; ++iter) {

    // Pre-compute random offsets
    if (ENABLE_MINI_BATCH && n >= TOTAL_BATCH_SIZE) {
      for (int d = 0; d < num_devices; ++d) {
        random_offsets[d] = rand() % devices[d].point_count;
      }
    }

#pragma omp parallel num_threads(num_devices)
    {
      int d = omp_get_thread_num();
      cudaSetDevice(d);

      // Reset Partial Sums
      for (int s = 0; s < NUM_STREAMS; ++s) {
        cudaMemsetAsync(devices[d].p_sum_x[s], 0, k * sizeof(double),
                        devices[d].streams[s]);
        cudaMemsetAsync(devices[d].p_sum_y[s], 0, k * sizeof(double),
                        devices[d].streams[s]);
        cudaMemsetAsync(devices[d].p_count[s], 0, k * sizeof(int),
                        devices[d].streams[s]);
      }

      // Compute Centroid Norms (Stream 0)
      int normBlocks = (k + 255) / 256;
      compute_centroid_norms<<<normBlocks, 256, 0, devices[d].streams[0]>>>(
          k, devices[d].centroids_x, devices[d].centroids_y,
          devices[d].d_c_norms);

      // Use event to sync norms
      cudaEvent_t normEvent;
      cudaEventCreate(&normEvent);
      cudaEventRecord(normEvent, devices[d].streams[0]);

      for (int s = 1; s < NUM_STREAMS; ++s) {
        cudaStreamWaitEvent(devices[d].streams[s], normEvent, 0);
      }

      // Distribute work among streams
      int stream_chunk_size =
          (devices[d].point_count + NUM_STREAMS - 1) / NUM_STREAMS;

      int local_offset = 0;
      if (ENABLE_MINI_BATCH && n >= TOTAL_BATCH_SIZE) {
        int target_local_batch = TOTAL_BATCH_SIZE / num_devices;
        // For mini-batch, we might iterate differently, but assuming exact for
        // check or standard mini-batch In mini-batch, we usually process
        // `target_local_batch` total. Let's assume point_count >
        // target_local_batch. We should just split `target_local_batch` among
        // streams? The check `local_batch_size` vs `point_count` logic is in
        // original code. Simplified: We always iterate over what we decided is
        // `local_batch_size`.

        local_offset = random_offsets[d];
        stream_chunk_size =
            (target_local_batch + NUM_STREAMS - 1) / NUM_STREAMS;
      }

      for (int s = 0; s < NUM_STREAMS; ++s) {
        int s_start = s * stream_chunk_size;
        int my_batch_limit = (ENABLE_MINI_BATCH && n >= TOTAL_BATCH_SIZE)
                                 ? (TOTAL_BATCH_SIZE / num_devices)
                                 : devices[d].point_count;

        int s_end = std::min(s_start + stream_chunk_size, my_batch_limit);
        int my_batch_size = s_end - s_start;

        if (my_batch_size <= 0)
          continue;

        for (int t_start = 0; t_start < my_batch_size; t_start += TILE_SIZE) {
          int t_end = std::min(t_start + TILE_SIZE, my_batch_size);
          int current_tile_size = t_end - t_start;

          int global_offset_in_batch = local_offset + s_start + t_start;
          int start_idx_in_buffer =
              global_offset_in_batch % devices[d].point_count;

          int contiguous_size = std::min(
              current_tile_size, devices[d].point_count - start_idx_in_buffer);

          for (int split = 0; split < 2; ++split) {
            int actual_size = (split == 0)
                                  ? contiguous_size
                                  : (current_tile_size - contiguous_size);
            if (actual_size <= 0)
              break;

            int current_idx = (split == 0) ? start_idx_in_buffer : 0;
            const double *d_points_x_ptr = devices[d].points_x + current_idx;
            const double *d_points_y_ptr = devices[d].points_y + current_idx;

            double alpha = -2.0;
            double beta = 0.0;

            cublasDgemm(devices[d].handles[s], CUBLAS_OP_N, CUBLAS_OP_T,
                        actual_size, k, 1, &alpha, d_points_x_ptr, actual_size,
                        devices[d].centroids_x, k, &beta, devices[d].d_dist[s],
                        actual_size);

            beta = 1.0;
            cublasDgemm(devices[d].handles[s], CUBLAS_OP_N, CUBLAS_OP_T,
                        actual_size, k, 1, &alpha, d_points_y_ptr, actual_size,
                        devices[d].centroids_y, k, &beta, devices[d].d_dist[s],
                        actual_size);

            // Find Nearest Centroid
            int assignBlocks = (actual_size + 255) / 256;

            if (fits_in_shared(k)) {
              size_t smemSize = k * (2 * sizeof(double) + sizeof(int));
              find_nearest_centroid_gemm_shared<<<assignBlocks, 256, smemSize,
                                                  devices[d].streams[s]>>>(
                  actual_size, k, devices[d].d_dist[s], devices[d].d_c_norms,
                  d_points_x_ptr, d_points_y_ptr, devices[d].p_sum_x[s],
                  devices[d].p_sum_y[s], devices[d].p_count[s]);
            } else {
              find_nearest_centroid_gemm<<<assignBlocks, 256, 0,
                                           devices[d].streams[s]>>>(
                  actual_size, k, devices[d].d_dist[s], devices[d].d_c_norms,
                  d_points_x_ptr, d_points_y_ptr, devices[d].p_sum_x[s],
                  devices[d].p_sum_y[s], devices[d].p_count[s]);
            }
          }
        }
      }

      cudaDeviceSynchronize(); // Wait for all streams to finish
      cudaEventDestroy(normEvent);

      // Reduction of Partial Sums
      // We perform this on Stream 0.

      // Need pointers array on device.
      // We can allocate them once, but here lets alloc temp.

      double **d_ptrs_sum_x, **d_ptrs_sum_y;
      int **d_ptrs_count;
      cudaMalloc(&d_ptrs_sum_x, NUM_STREAMS * sizeof(double *));
      cudaMalloc(&d_ptrs_sum_y, NUM_STREAMS * sizeof(double *));
      cudaMalloc(&d_ptrs_count, NUM_STREAMS * sizeof(int *));

      std::vector<double *> h_ptrs_sum_x(NUM_STREAMS),
          h_ptrs_sum_y(NUM_STREAMS);
      std::vector<int *> h_ptrs_count(NUM_STREAMS);
      for (int s = 0; s < NUM_STREAMS; ++s) {
        h_ptrs_sum_x[s] = devices[d].p_sum_x[s];
        h_ptrs_sum_y[s] = devices[d].p_sum_y[s];
        h_ptrs_count[s] = devices[d].p_count[s];
      }
      cudaMemcpyAsync(d_ptrs_sum_x, h_ptrs_sum_x.data(),
                      NUM_STREAMS * sizeof(double *), cudaMemcpyHostToDevice,
                      devices[d].streams[0]);
      cudaMemcpyAsync(d_ptrs_sum_y, h_ptrs_sum_y.data(),
                      NUM_STREAMS * sizeof(double *), cudaMemcpyHostToDevice,
                      devices[d].streams[0]);
      cudaMemcpyAsync(d_ptrs_count, h_ptrs_count.data(),
                      NUM_STREAMS * sizeof(int *), cudaMemcpyHostToDevice,
                      devices[d].streams[0]);

      // Zero out main accumulation buffers first? No, we write directly to them
      // in `reduce`? No, `reduce_partial_sums` writes to `final_sum_x`. We need
      // to zero them? No, reduce writes the SUM. But `final_sum_x` is
      // `devices[d].sum_x`. The reduce kernel overwrites the destination.

      int reduceBlocks = (k + 255) / 256;
      reduce_partial_sums<<<reduceBlocks, 256, 0, devices[d].streams[0]>>>(
          k, NUM_STREAMS, d_ptrs_sum_x, d_ptrs_sum_y, d_ptrs_count,
          devices[d].sum_x, devices[d].sum_y, devices[d].count);

      cudaStreamSynchronize(devices[d].streams[0]);
      cudaFree(d_ptrs_sum_x);
      cudaFree(d_ptrs_sum_y);
      cudaFree(d_ptrs_count);

#pragma omp barrier
    }

    // Reduction Phase: Compute new centroids on GPU 0
    cudaSetDevice(0);
    int updateBlockSize = 256;
    int updateNumBlocks = (k + updateBlockSize - 1) / updateBlockSize;

    update_centroid_positions<<<updateNumBlocks, updateBlockSize, 0,
                                devices[0].streams[0]>>>(
        k, num_devices, d_gather_sum_x, d_gather_sum_y, d_gather_count,
        devices[0].centroids_x, devices[0].centroids_y);
    cudaStreamSynchronize(devices[0].streams[0]);

// Broadcast Phase: Centroids (GPU 0 -> Peers)
#pragma omp parallel num_threads(num_devices)
    {
      int d = omp_get_thread_num();
      if (d > 0) {
        cudaSetDevice(d);
        // Peer Copy: updates local centroids from GPU 0's centroids
        cudaMemcpyPeerAsync(devices[d].centroids_x, d, devices[0].centroids_x,
                            0, k * sizeof(double), devices[d].streams[0]);
        cudaMemcpyPeerAsync(devices[d].centroids_y, d, devices[0].centroids_y,
                            0, k * sizeof(double), devices[d].streams[0]);
        cudaStreamSynchronize(devices[d].streams[0]);
      }
#pragma omp barrier
    }

    // Copy updated centroids from GPU 0 → host
    cudaMemcpy(host_centroids_x.data(), devices[0].centroids_x,
               k * sizeof(double), cudaMemcpyDeviceToHost);
    cudaMemcpy(host_centroids_y.data(), devices[0].centroids_y,
               k * sizeof(double), cudaMemcpyDeviceToHost);
    // Store in history array at position for this iteration
    for (int j = 0; j < k; ++j) {
      host_memory_x[(iter + 1) * k + j] = host_centroids_x[j];
      host_memory_y[(iter + 1) * k + j] = host_centroids_y[j];
    }
  }

  runtime = get_time() - runtime;
  printf("Time Elapsed: %f s\n", runtime);
  write_memory("memory.out", niters, host_memory_x.data(), host_memory_y.data(),
               k);

  // Cleanup
  cudaFreeHost(pinned_x);
  cudaFreeHost(pinned_y);

#pragma omp parallel num_threads(num_devices)
  {
    int d = omp_get_thread_num();
    cudaSetDevice(d);

    for (int s = 0; s < NUM_STREAMS; ++s) {
      cublasDestroy(devices[d].handles[s]);
      cudaStreamDestroy(devices[d].streams[s]);
      cudaFree(devices[d].d_dist[s]);
      cudaFree(devices[d].p_sum_x[s]);
      cudaFree(devices[d].p_sum_y[s]);
      cudaFree(devices[d].p_count[s]);
    }
    cudaFree(devices[d].d_c_norms);
  }

  return EXIT_SUCCESS;
}