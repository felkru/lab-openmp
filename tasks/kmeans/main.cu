#include <cfloat>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cublas_v2.h>
#include <cuda_runtime.h>
#include <fstream>
#include <string>
#include <sys/time.h>
#include <vector>
#include <iostream>
#include <algorithm>
#include <omp.h>

#define DEFAULT_K 5
#define DEFAULT_NITERS 20
<<<<<<< HEAD
=======
#define TOTAL_BATCH_SIZE 250000
#define TILE_SIZE 2048 // Tile size for cuBLAS GEMM
>>>>>>> f27b3ef88a61c26dc198bad9d614b9849df92efe

#define cudaCheck(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true) {
   if (code != cudaSuccess) {
      fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}

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

<<<<<<< HEAD
void write_memory(std::string filename, int niters, const double *mx, const double *my, int k) {
=======
// Helper to check if K fits in shared memory (Max 48KB usually, safe bet 32KB)
// K * (sizeof(double)*2 + sizeof(int)) = K * 20 bytes.
// 32000 / 20 = 1600.
bool fits_in_shared(int k) {
  return (k * (sizeof(double) * 2 + sizeof(int))) < (32 * 1024);
}

void write_memory(std::string filename, int niters, double *memory_x,
                  double *memory_y, int k) {
>>>>>>> f27b3ef88a61c26dc198bad9d614b9849df92efe
  std::ofstream outfile{filename};
  for (int iter = 0; iter < niters + 1; ++iter) {
    for (int i = 0; i < k; ++i) {
      outfile << iter << ' ' << mx[iter * k + i] << ' ' << my[iter * k + i] << '\n';
    }
  }
}

void init_centroids(double *centroids_x, double *centroids_y, int k, int d) {
  for (int i = 0; i < k; ++i) {
    centroids_x[i] = rand() % d;
    centroids_y[i] = rand() % d;
  }
}

<<<<<<< HEAD
__global__ void compute_thresholds(int k, const double *cx, const double *cy, double *t) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= k) return;
  double min_dist = DBL_MAX;
  for (int j = 0; j < k; ++j) {
    if (i == j) continue;
    double dx = cx[i] - cx[j], dy = cy[i] - cy[j];
    double d = sqrt(dx * dx + dy * dy);
    if (d < min_dist) min_dist = d;
=======
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
>>>>>>> f27b3ef88a61c26dc198bad9d614b9849df92efe
  }
  t[i] = 0.5 * min_dist;
}

// Optimized Kernel with Shared Memory Tiling for Centroids
// FIXED: Removed early returns to ensure all threads reach __syncthreads()
__global__ void determine_nearest_centroid(int n, int k, const double *px, const double *py,
                                          const double *__restrict__ cx, const double *__restrict__ cy,
                                          int *__restrict__ assignments, const double *__restrict__ thresholds, bool use_filtering,
                                          double *sum_x, double *sum_y, int *count) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  bool valid = (i < n);
  bool process = valid;

  double x = 0, y = 0;
  int old_c = -1;
  if (valid) {
    x = px[i]; y = py[i];
    old_c = assignments[i];
  }

  // 1. Filtering (Triangle Inequality)
  if (valid && use_filtering && old_c >= 0 && old_c < k) {
    double dx = x - cx[old_c], dy = y - cy[old_c];
    if (sqrt(dx * dx + dy * dy) <= thresholds[old_c]) {
      atomicAdd(&sum_x[old_c], x);
      atomicAdd(&sum_y[old_c], y);
      atomicAdd(&count[old_c], 1);
      process = false; // Skip full search but MUST CONTINUE to sync points
    }
  }

  // 2. Full Search with Tiling
  double min_dist_sq = DBL_MAX;
  int best_c = 0;

  // Shared Memory Tiling for Centroids
  // H100 Optimization: Increased to 2048 (32KB) to fit within 48KB static limit
  const int TILE_SIZE = 2048; 
  __shared__ double s_cx[TILE_SIZE];
  __shared__ double s_cy[TILE_SIZE];

  for (int k_start = 0; k_start < k; k_start += TILE_SIZE) {
    int limit = min(TILE_SIZE, k - k_start);
    // Cooperative load (ALL threads must execute this)
    for (int t = threadIdx.x; t < limit; t += blockDim.x) {
      s_cx[t] = cx[k_start + t];
      s_cy[t] = cy[k_start + t];
    }
    __syncthreads();

    if (process) {
      for (int j = 0; j < limit; ++j) {
        double dx = x - s_cx[j], dy = y - s_cy[j];
        double d2 = dx * dx + dy * dy;
        if (d2 < min_dist_sq) {
          min_dist_sq = d2;
          best_c = k_start + j;
        }
      }
    }
    __syncthreads();
  }

  if (process) {
    assignments[i] = best_c;
    atomicAdd(&sum_x[best_c], x);
    atomicAdd(&sum_y[best_c], y);
    atomicAdd(&count[best_c], 1);
  }
}

// ---------------- DEVICE DATA STRUCT ----------------
struct DeviceData {
<<<<<<< HEAD
    int id;
    int point_count; // total points / num_devices               
    double *points_x, *points_y;       
    double *centroids_x, *centroids_y; 
    double *sum_x, *sum_y;             
    int *count;
    double *t, *sx, *sy;
    int *assign;
    cudaStream_t stream;
=======
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
>>>>>>> f27b3ef88a61c26dc198bad9d614b9849df92efe
};

int main(int argc, char **argv) {
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

  read_points(argv[1], host_points_x.data(), host_points_y.data(), n);
  init_centroids(host_centroids_x.data(), host_centroids_y.data(), k, dim);

  std::vector<double> host_memory_x((niters + 1) * k), host_memory_y((niters + 1) * k);
  for (int j = 0; j < k; ++j) {
    host_memory_x[j] = host_centroids_x[j];
    host_memory_y[j] = host_centroids_y[j];
  }

  // would now directly start the computation on cpu.
  // but for gpu usage need to distribute data onto the gpus
  // use cuda calls instead of openmp for that

<<<<<<< HEAD
  int num_devices = 3;
=======
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
>>>>>>> f27b3ef88a61c26dc198bad9d614b9849df92efe

  // 1 OpenMP Thread = 1 GPU
  omp_set_num_threads(num_devices);
  std::vector<DeviceData> devices(num_devices);
  int points_per_gpu = (n + num_devices - 1) / num_devices; // divide points evenly accross all gpus

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
<<<<<<< HEAD
    cudaCheck(cudaSetDevice(d));
    cudaCheck(cudaStreamCreate(&devices[d].stream)); // Create a stream of data for each gpu
=======
    cudaSetDevice(d);
    // Initialize specific device and streams
>>>>>>> f27b3ef88a61c26dc198bad9d614b9849df92efe
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
    cudaCheck(cudaMalloc(&devices[d].points_x, devices[d].point_count * sizeof(double)));
    cudaCheck(cudaMalloc(&devices[d].points_y, devices[d].point_count * sizeof(double)));
      
    // Copy points from cpu to gpu
<<<<<<< HEAD
    //  cudaMemcpyHostToDevice is an enum
    cudaCheck(cudaMemcpyAsync(devices[d].points_x, pinned_x + start, devices[d].point_count * sizeof(double), cudaMemcpyHostToDevice, devices[d].stream));
    cudaCheck(cudaMemcpyAsync(devices[d].points_y, pinned_y + start, devices[d].point_count * sizeof(double), cudaMemcpyHostToDevice, devices[d].stream));
      
    // Allocate space for centroids, sums, and counts Aux
    cudaCheck(cudaMalloc(&devices[d].centroids_x, k * sizeof(double)));
    cudaCheck(cudaMalloc(&devices[d].centroids_y, k * sizeof(double)));
    cudaCheck(cudaMalloc(&devices[d].sum_x, k * sizeof(double)));
    cudaCheck(cudaMalloc(&devices[d].sum_y, k * sizeof(double)));
    cudaCheck(cudaMalloc(&devices[d].count, k * sizeof(int)));
      
    // Copy initial centroids from CPU to each GPU
    cudaCheck(cudaMemcpyAsync(devices[d].centroids_x, host_centroids_x.data(), k * sizeof(double), cudaMemcpyHostToDevice, devices[d].stream));
    cudaCheck(cudaMemcpyAsync(devices[d].centroids_y, host_centroids_y.data(), k * sizeof(double), cudaMemcpyHostToDevice, devices[d].stream));
      
    // Like a barrier in openmp. Waits until all preceding commands are done.
    // make sure that the data is copied before continuing
    cudaCheck(cudaStreamSynchronize(devices[d].stream));

    cudaCheck(cudaMalloc(&devices[d].t, k * sizeof(double)));
    cudaCheck(cudaMalloc(&devices[d].sx, k * sizeof(double)));
    cudaCheck(cudaMalloc(&devices[d].sy, k * sizeof(double)));
    cudaCheck(cudaMalloc(&devices[d].assign, devices[d].point_count * sizeof(int)));
    cudaCheck(cudaMemsetAsync(devices[d].assign, -1, devices[d].point_count * sizeof(int), devices[d].stream));

    // Like a barrier in openmp. Waits until all preceding commands are done.
    // make sure that the data is copied before continuing
    cudaCheck(cudaStreamSynchronize(devices[d].stream));
=======
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
>>>>>>> f27b3ef88a61c26dc198bad9d614b9849df92efe

    // P2P not strictly needed for CPU-based reduction
    cudaCheck(cudaStreamSynchronize(devices[d].stream));
    #pragma omp barrier
  }

  // Alloc gathering buffers (2D host-side partial results)
  std::vector<double> partial_sum_x(num_devices * k), partial_sum_y(num_devices * k);
  std::vector<int> partial_count(num_devices * k);

  printf("Executing k-means à %d iterations (%d GPUs)...\n", niters, num_devices);
  double runtime = get_time();

<<<<<<< HEAD
  // Compute Phase: 
  // Cannot be parallelized since it depends on the previous iteration
  for (int iter = 0; iter < niters; ++iter) {
    #pragma omp parallel num_threads(num_devices)
    {
      int d = omp_get_thread_num();
      cudaSetDevice(d);
          
      // Reset sum_0[x] = 0
      // Reset sum_0[x] = 0
      // Reset count[x] = 0
      cudaMemsetAsync(devices[d].sum_x, 0, k * sizeof(double), devices[d].stream);
      cudaMemsetAsync(devices[d].sum_y, 0, k * sizeof(double), devices[d].stream);
      cudaMemsetAsync(devices[d].count, 0, k * sizeof(int), devices[d].stream);
      
      int local_batch_size = devices[d].point_count;

      int blockSize = 256;
      if (iter > 0) {
        int numBlocksThresholds = (k + blockSize - 1) / blockSize;
        compute_thresholds<<<numBlocksThresholds, blockSize, 0, devices[d].stream>>>(k, devices[d].centroids_x, devices[d].centroids_y, devices[d].t);
      }
      
      int numBlocksMain = (local_batch_size + blockSize - 1) / blockSize;
      determine_nearest_centroid<<<numBlocksMain, blockSize, 0, devices[d].stream>>>(
        local_batch_size, k, devices[d].points_x, 
        devices[d].points_y, devices[d].centroids_x, 
        devices[d].centroids_y, devices[d].assign, 
        devices[d].t, (iter > 0), devices[d].sum_x, devices[d].sum_y, devices[d].count);
      cudaCheck(cudaGetLastError());
      cudaCheck(cudaStreamSynchronize(devices[d].stream));
      }

    // Reduction Phase: Collect from all GPUs to CPU in parallel
    #pragma omp parallel num_threads(num_devices)
    {
      int d = omp_get_thread_num();
      cudaSetDevice(d);
      cudaMemcpy(partial_sum_x.data() + d * k, devices[d].sum_x, k * sizeof(double), cudaMemcpyDeviceToHost);
      cudaMemcpy(partial_sum_y.data() + d * k, devices[d].sum_y, k * sizeof(double), cudaMemcpyDeviceToHost);
      cudaMemcpy(partial_count.data() + d * k, devices[d].count, k * sizeof(int), cudaMemcpyDeviceToHost);
=======
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
>>>>>>> f27b3ef88a61c26dc198bad9d614b9849df92efe
    }

    // Aggregate results from all devices in parallel
    #pragma omp parallel for num_threads(num_devices)
    for (int j = 0; j < k; ++j) {
      double total_sum_x = 0.0, total_sum_y = 0.0;
      int total_count = 0;
      for (int d = 0; d < num_devices; ++d) {
        total_sum_x += partial_sum_x[d * k + j];
        total_sum_y += partial_sum_y[d * k + j];
        total_count += partial_count[d * k + j];
      }
      if (total_count > 0) {
        host_centroids_x[j] = total_sum_x / total_count;
        host_centroids_y[j] = total_sum_y / total_count;
      }
    }

    // Broadcast Phase: Copy new centroids to all GPUs
    #pragma omp parallel num_threads(num_devices)
    {
      int d = omp_get_thread_num();
      cudaSetDevice(d);
      cudaMemcpyAsync(devices[d].centroids_x, host_centroids_x.data(), k * sizeof(double), cudaMemcpyHostToDevice, devices[d].stream);
      cudaMemcpyAsync(devices[d].centroids_y, host_centroids_y.data(), k * sizeof(double), cudaMemcpyHostToDevice, devices[d].stream);
      cudaStreamSynchronize(devices[d].stream);
    }

    // Store in history array
    for (int j = 0; j < k; ++j) {
      host_memory_x[(iter + 1) * k + j] = host_centroids_x[j];
      host_memory_y[(iter + 1) * k + j] = host_centroids_y[j];
    }
  }

  runtime = get_time() - runtime;
  printf("Time Elapsed: %f s\n", runtime);
  write_memory("memory.out", niters, host_memory_x.data(), host_memory_y.data(), k);

  // Cleanup
  cudaFreeHost(pinned_x); cudaFreeHost(pinned_y);
  for(int d=0; d<num_devices; ++d) {
      cudaSetDevice(devices[d].id);
      cudaFree(devices[d].points_x); cudaFree(devices[d].points_y); cudaFree(devices[d].assign);
      cudaFree(devices[d].centroids_x); cudaFree(devices[d].centroids_y); cudaFree(devices[d].t);
      cudaFree(devices[d].sum_x); cudaFree(devices[d].sum_y); cudaFree(devices[d].count);
      cudaFree(devices[d].sx); cudaFree(devices[d].sy);
      cudaStreamDestroy(devices[d].stream);
  }

<<<<<<< HEAD
  return 0;
=======
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
>>>>>>> f27b3ef88a61c26dc198bad9d614b9849df92efe
}