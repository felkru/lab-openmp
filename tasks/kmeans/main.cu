#include <algorithm>
#include <cfloat>
#include <cmath>
#include <cstdio>
#include <cstdlib>
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

// Update centroid positions (same logic as CPU version)
__global__ void determine_nearest_centroid(
    int batch_size, // How many points to process THIS iteration
    int n_local,    // Total points on this GPU
    int k,          // Number of centroids
    int offset,     // Starting position in the data
    const double *__restrict__ points_x, const double *__restrict__ points_y,
    const double *__restrict__ centroids_x,
    const double *__restrict__ centroids_y, double *sum_x, double *sum_y,
    int *count) {
  // idx is the index of the point
  // blockDim How many threads per block
  // used to index each thread in the block
  int idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < batch_size) { // only compute a subset of the points
    // Offset logic for Local Data Partition
    int i = (offset + idx) % n_local;

    double px = points_x[i];
    double py = points_y[i];
    double optimal_dist_sq = DBL_MAX;
    int assignment = 0;

    for (int j = 0; j < k; ++j) {
      double dx = px - centroids_x[j];
      double dy = py - centroids_y[j];
      double dist_sq = dx * dx + dy * dy; // Squared distance

      if (dist_sq < optimal_dist_sq) {
        optimal_dist_sq = dist_sq;
        assignment = j;
      }
    }

    // Write block results to global memory. one atomic operation per
    // centroid/thread
    atomicAdd(&sum_x[assignment], px);
    atomicAdd(&sum_y[assignment], py);
    atomicAdd(&count[assignment], 1);
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
  cudaStream_t stream;
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

  int num_devices = 4;
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
    cudaStreamCreate(
        &devices[d].stream); // Create a stream of data for each gpu
    devices[d].id = d;

    int start = d * points_per_gpu;
    int end = std::min(start + points_per_gpu, n);
    devices[d].point_count = end - start;

    // Allocate space for points
    cudaMalloc(&devices[d].points_x, devices[d].point_count * sizeof(double));
    cudaMalloc(&devices[d].points_y, devices[d].point_count * sizeof(double));

    // Copy points from cpu to gpu
    //  cudaMemcpyHostToDevice is an enum
    cudaMemcpyAsync(devices[d].points_x, pinned_x + start,
                    devices[d].point_count * sizeof(double),
                    cudaMemcpyHostToDevice, devices[d].stream);
    cudaMemcpyAsync(devices[d].points_y, pinned_y + start,
                    devices[d].point_count * sizeof(double),
                    cudaMemcpyHostToDevice, devices[d].stream);

    // Allocate space for centroids, sums, and counts Aux
    cudaMalloc(&devices[d].centroids_x, k * sizeof(double));
    cudaMalloc(&devices[d].centroids_y, k * sizeof(double));
    cudaMalloc(&devices[d].sum_x, k * sizeof(double));
    cudaMalloc(&devices[d].sum_y, k * sizeof(double));
    cudaMalloc(&devices[d].count, k * sizeof(int));

    // Copy initial centroids from CPU to each GPU
    cudaMemcpyAsync(devices[d].centroids_x, host_centroids_x.data(),
                    k * sizeof(double), cudaMemcpyHostToDevice,
                    devices[d].stream);
    cudaMemcpyAsync(devices[d].centroids_y, host_centroids_y.data(),
                    k * sizeof(double), cudaMemcpyHostToDevice,
                    devices[d].stream);

    // Like a barrier in openmp. Waits until all preceding commands are done.
    // make sure that the data is copied before continuing
    cudaStreamSynchronize(devices[d].stream);

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
  //  Cannot be parallelized since it depends on the previous iteration
  for (int iter = 0; iter < niters; ++iter) {

    // Pre-compute random offsets BEFORE parallel region (rand() not
    // thread-safe)
    if (ENABLE_MINI_BATCH && n >= TOTAL_BATCH_SIZE) {
      for (int d = 0; d < num_devices; ++d) {
        random_offsets[d] = rand() % devices[d].point_count;
      }
    }

// 1. Parallel Compute on Local Batches
#pragma omp parallel num_threads(num_devices)
    {
      int d = omp_get_thread_num();
      cudaSetDevice(d);

      // Reset sum_0[x] = 0
      // Reset sum_0[x] = 0
      // Reset count[x] = 0
      cudaMemsetAsync(devices[d].sum_x, 0, k * sizeof(double),
                      devices[d].stream);
      cudaMemsetAsync(devices[d].sum_y, 0, k * sizeof(double),
                      devices[d].stream);
      cudaMemsetAsync(devices[d].count, 0, k * sizeof(int), devices[d].stream);

      // Distribute Batch Logic
      int local_batch_size;
      int local_offset;

      if (!ENABLE_MINI_BATCH || n < TOTAL_BATCH_SIZE) {
        // Exac K-Means: process ALL points every iteration
        local_batch_size = devices[d].point_count;
        local_offset = 0;
      } else {
        // Mini-Batch K-Means: random sampling with srand(1234)
        int target_local_batch = TOTAL_BATCH_SIZE / num_devices;
        local_batch_size = target_local_batch;
        local_offset = random_offsets[d]; // Use pre-computed random offset
      }

      // Use 256 Threads per block
      // divide the num of points with the number of threads to get the total
      // number of blocks this computation runs on 256 Threads per Streaming
      // Multiprocessor supported on H100's The GPU scheduler decides which
      // blocks go to which SMs
      int blockSize = 256;
      int numBlocks = (local_batch_size + blockSize - 1) / blockSize;

      determine_nearest_centroid<<<numBlocks, blockSize, 0,
                                   devices[d].stream>>>(
          local_batch_size, devices[d].point_count, k, local_offset,
          devices[d].points_x, devices[d].points_y, devices[d].centroids_x,
          devices[d].centroids_y, devices[d].sum_x, devices[d].sum_y,
          devices[d].count);

      cudaStreamSynchronize(devices[d].stream);
// wait till each computation is done
#pragma omp barrier
    }

    // Reduction Phase: Compute new centroids on GPU 0
    // Use 256 Threads per block
    // divide the num of points with the number of threads to get the total
    // number of blocks this computation runs on 256 Threads per Streaming
    // Multiprocessor supported on H100's The GPU scheduler decides which blocks
    // go to which SMs
    cudaSetDevice(0);
    int updateBlockSize = 256;
    int updateNumBlocks = (k + updateBlockSize - 1) / updateBlockSize;

    update_centroid_positions<<<updateNumBlocks, updateBlockSize, 0,
                                devices[0].stream>>>(
        k, num_devices, d_gather_sum_x, d_gather_sum_y, d_gather_count,
        devices[0].centroids_x, devices[0].centroids_y);
    cudaStreamSynchronize(devices[0].stream);

// Broadcast Phase: Centroids (GPU 0 -> Peers)
#pragma omp parallel num_threads(num_devices)
    {
      int d = omp_get_thread_num();
      if (d > 0) {
        cudaSetDevice(d);
        // Peer Copy: updates local centroids from GPU 0's centroids
        cudaMemcpyPeerAsync(devices[d].centroids_x, d, devices[0].centroids_x,
                            0, k * sizeof(double), devices[d].stream);
        cudaMemcpyPeerAsync(devices[d].centroids_y, d, devices[0].centroids_y,
                            0, k * sizeof(double), devices[d].stream);
        cudaStreamSynchronize(devices[d].stream);
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

  return EXIT_SUCCESS;
}