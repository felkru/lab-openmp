#include <cfloat>
#include <cmath>
#include <cstdio>
#include <cstdlib>
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

void write_memory(std::string filename, int niters, const double *mx, const double *my, int k) {
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

__global__ void compute_thresholds(int k, const double *cx, const double *cy, double *t) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= k) return;
  double min_dist = DBL_MAX;
  for (int j = 0; j < k; ++j) {
    if (i == j) continue;
    double dx = cx[i] - cx[j], dy = cy[i] - cy[j];
    double d = sqrt(dx * dx + dy * dy);
    if (d < min_dist) min_dist = d;
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
    int id;
    int point_count; // total points / num_devices               
    double *points_x, *points_y;       
    double *centroids_x, *centroids_y; 
    double *sum_x, *sum_y;             
    int *count;
    double *t, *sx, *sy;
    int *assign;
    cudaStream_t stream;
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

  int num_devices = 3;

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
    cudaCheck(cudaSetDevice(d));
    cudaCheck(cudaStreamCreate(&devices[d].stream)); // Create a stream of data for each gpu
    devices[d].id = d;

    int start = d * points_per_gpu;
    int end = std::min(start + points_per_gpu, n);
    devices[d].point_count = end - start;

     // Allocate space for points
    cudaCheck(cudaMalloc(&devices[d].points_x, devices[d].point_count * sizeof(double)));
    cudaCheck(cudaMalloc(&devices[d].points_y, devices[d].point_count * sizeof(double)));
      
    // Copy points from cpu to gpu
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

    // P2P not strictly needed for CPU-based reduction
    cudaCheck(cudaStreamSynchronize(devices[d].stream));
    #pragma omp barrier
  }

  // Alloc gathering buffers (2D host-side partial results)
  std::vector<double> partial_sum_x(num_devices * k), partial_sum_y(num_devices * k);
  std::vector<int> partial_count(num_devices * k);

  printf("Executing k-means à %d iterations (%d GPUs)...\n", niters, num_devices);
  double runtime = get_time();

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

  return 0;
}