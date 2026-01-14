#include <cstdio>
#include <cstdlib>
#include <vector>
#include <fstream>
#include <string>
#include <cfloat>
#include <cmath>
#include <sys/time.h>
#include <cuda_runtime.h>
#include <omp.h> 

#define DEFAULT_K 5
#define DEFAULT_NITERS 20

double get_time() {
    struct timeval tv;
    gettimeofday(&tv, (struct timezone*)0);
    return ((double)tv.tv_sec + (double)tv.tv_usec / 1000000.0 );
}

void read_points(std::string filename, double* px, double* py, int n){
    std::ifstream infile{filename};
    double x, y;
    int i = 0;
    while (infile >> x >> y) {
        if (i >= n) {
            printf("WARNING: more points in input file '%s' than read: stopping after %d lines\n", filename.c_str(), i);
            return;
        }
        px[i] = x;
        py[i] = y;
        i++;
    }
}

void write_memory(std::string filename, int niters, double* memory_x, double* memory_y, int k){
    std::ofstream outfile{filename};
    for (int iter = 0; iter < niters + 1; ++iter) {
        for (int i = 0; i < k; ++i) {
            outfile << iter << ' ' << memory_x[iter * k + i] << ' ' << memory_y[iter * k + i] << '\n';
        }
    }
}

void init_centroids(double *centroids_x, double *centroids_y, int k, int d){
    for (int i = 0; i < k; ++i) {
        centroids_x[i] = rand() % d;
        centroids_y[i] = rand() % d;
    }
}


__global__ void determine_nearest_centroid(int n, int k, 
                                    const double* __restrict__ points_x, 
                                    const double* __restrict__ points_y, 
                                    const double* __restrict__ centroids_x, 
                                    const double* __restrict__ centroids_y, 
                                    double* sum_x, double* sum_y, int* count) 
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    
    // Find nearest centroid (same logic as CPU version)
    double optimal_dist = DBL_MAX;
    int assignment = 0;

    // find smallest distance to centroid
    for (int j = 0; j < k; ++j) {
        double dist = std::sqrt(
            std::pow(points_x[i] - centroids_x[j], 2) +
            std::pow(points_y[i] - centroids_y[j], 2)
        );
        
        if (dist < optimal_dist) {
            optimal_dist = dist;
            assignment = j;
        }
    }

    // Accumulate point to its assigned centroid
    // thread-safe addition that prevents race conditions.
    atomicAdd(&sum_x[assignment], points_x[i]);
    atomicAdd(&sum_y[assignment], points_y[i]);
    atomicAdd(&count[assignment], 1);
}

// Update centroid positions (same logic as CPU version)
// Only difference is the logic to access the data from the arrays
__global__ void update_centroid_positions(int k, int num_devices,
                                     double** all_sum_x, double** all_sum_y, int** all_count,
                                     double* centroids_x, double* centroids_y)
{
    // j is the index of the centroid
    int j = blockIdx.x * blockDim.x + threadIdx.x;
    if (j >= k) return;

    int count = 0;
    double sum_x = 0.0;
    double sum_y = 0.0;

    for(int d=0; d<num_devices; ++d) {
        count += all_count[d][j];
        sum_x += all_sum_x[d][j];
        sum_y += all_sum_y[d][j];
    }

    // Update centroid position
    if (count != 0) {
        centroids_x[j] = sum_x / count;
        centroids_y[j] = sum_y / count;
    }
}

int main(int argc, const char* argv[]) {
    srand(1234);
    if (argc < 4 || argc > 6) {
        printf("Usage: %s <input file> <size dimensions> <num points> <num centroids> <num iters>\n", argv[0]);
        return EXIT_FAILURE;
    }

    const int dim = atoi(argv[2]); // number of dimensions
    const char * input_file = argv[1]; // input file
    const int n = atoi(argv[3]); // number of points
    const int k = (argc > 4 ? atoi(argv[4]) : DEFAULT_K); // number of centroids
    const int niters = (argc > 5 ? atoi(argv[5]) : DEFAULT_NITERS); // number of iterations

    // Initilise and load Host Data Points and Centroids
    // [x0, y0, x1, y1, x2, y2, ...] -> [x0, x1, x2, ...] AND [y0, y1, y2, ...]
    std::vector<double> host_points_x(n), host_points_y(n);
    std::vector<double> host_centroids_x(k), host_centroids_y(k);

    read_points(input_file, host_points_x.data(), host_points_y.data(), n);
    init_centroids(host_centroids_x.data(), host_centroids_y.data(), k, dim);

    std::vector<double> host_memory_x((niters+1)*k), host_memory_y((niters+1)*k);
    for(int j=0; j<k; ++j) {
        host_memory_x[j] = host_centroids_x[j];
        host_memory_y[j] = host_centroids_y[j];
    }

    // would now directly start the computation on cpu. 
    // but for gpu usage need to distribute data onto the gpus
    // use cuda calls instead of openmp for that 

    // MULTI-GPU SETUP
    int num_devices = 0;
    cudaGetDeviceCount(&num_devices);
    if (num_devices > 4) num_devices = 4;
    printf("Using %d GPUs (DOUBLE PRECISION - SIMPLE KERNEL).\n", num_devices);
    if (num_devices < 1) return EXIT_FAILURE;

    // Per-GPU data structure. similar to data on host cpu
    struct DeviceData {
        int id;
        int point_count;                   // Number of points on this GPU
        double *points_x, *points_y;       // Points assigned to this GPU
        double *centroids_x, *centroids_y; // Centroid positions
        double *sum_x, *sum_y;             // Partial sums for reduction
        int *count;                        // Partial counts for reduction
        cudaStream_t stream;
    };

    std::vector<DeviceData> devices(num_devices);
    int points_per_gpu = (n + num_devices - 1) / num_devices; // divide points evenly accross all gpus

    // cudaMallocHost nessesary for the use of streams and memcpy
    double *pinned_points_x, *pinned_points_y;
    cudaMallocHost(&pinned_points_x, n * sizeof(double));
    cudaMallocHost(&pinned_points_y, n * sizeof(double));
    
    // Direct copy (no conversion needed for double)
    memcpy(pinned_points_x, host_points_x.data(), n * sizeof(double));
    memcpy(pinned_points_y, host_points_y.data(), n * sizeof(double));

    // Alloc and Copy Points to each GPU
    for(int d=0; d<num_devices; ++d) {
        devices[d].id = d;
        cudaSetDevice(d);
        cudaStreamCreate(&devices[d].stream); // Create a stream of data for each gpu
        
        int start = d * points_per_gpu;
        int end = std::min(start + points_per_gpu, n);
        devices[d].point_count = end - start;
        
        // Allocate space for points
        cudaMalloc(&devices[d].points_x, devices[d].point_count * sizeof(double));
        cudaMalloc(&devices[d].points_y, devices[d].point_count * sizeof(double));
        
        //Copy points from cpu to gpu
        // cudaMemcpyHostToDevice is an enum
        cudaMemcpyAsync(devices[d].points_x, pinned_points_x + start, devices[d].point_count * sizeof(double), cudaMemcpyHostToDevice, devices[d].stream);
        cudaMemcpyAsync(devices[d].points_y, pinned_points_y + start, devices[d].point_count * sizeof(double), cudaMemcpyHostToDevice, devices[d].stream);

        // Allocate space for centroids, sums, and counts
        cudaMalloc(&devices[d].centroids_x, k * sizeof(double));
        cudaMalloc(&devices[d].centroids_y, k * sizeof(double));
        cudaMalloc(&devices[d].sum_x, k * sizeof(double));
        cudaMalloc(&devices[d].sum_y, k * sizeof(double));
        cudaMalloc(&devices[d].count, k * sizeof(int));

        // Copy initial centroids from CPU to each GPU
        cudaMemcpyAsync(devices[d].centroids_x, host_centroids_x.data(), k * sizeof(double), cudaMemcpyHostToDevice, devices[d].stream);
        cudaMemcpyAsync(devices[d].centroids_y, host_centroids_y.data(), k * sizeof(double), cudaMemcpyHostToDevice, devices[d].stream);
    }


    #pragma omp parallel num_threads(num_devices)
    {
        int d = omp_get_thread_num();
        if(d < num_devices) {
            cudaSetDevice(d);
            
            // Like a barrier in openmp. Waits until all preceding commands are done.
            // make sure that the data is copied before continuing
            cudaStreamSynchronize(devices[d].stream);
            
            // Enable GPU to GPU Transfer via NVLink 
            for(int peer=0; peer<num_devices; ++peer) {
                if (d != peer) {
                    cudaDeviceEnablePeerAccess(peer, 0);
                }
            }
        }
    }
    
    // Alloc gather buffers on GPU 0 for reduction across all GPUs
    // Also need to store the count since we need to average the points.
    // And different GPUs can have different number of points and so also different 
    // number of count values.
    // For the computation
    // new_centroid_x = total_sum_x / total_count
    // new_centroid_y = total_sum_y / total_count
    double *gather_sum_x[4], *gather_sum_y[4];
    int *gather_count[4];
    cudaSetDevice(0);
    // Allocate Acual Data for the results of each GPU on GPU 0
    for (int d = 0; d < num_devices; ++d) {
        cudaMalloc(&gather_sum_x[d], k * sizeof(double));
        cudaMalloc(&gather_sum_y[d], k * sizeof(double));
        cudaMalloc(&gather_count[d], k * sizeof(int));
    }
    
    // Allocate Pointers for the Data for each GPU on GPU 0
    double **d_gather_sum_x, **d_gather_sum_y;
    int **d_gather_count;
    cudaMalloc(&d_gather_sum_x, num_devices * sizeof(double*));
    cudaMalloc(&d_gather_sum_y, num_devices * sizeof(double*));
    cudaMalloc(&d_gather_count, num_devices * sizeof(int*));
    // Copy these Pointers from CPU to GPU 0 
    cudaMemcpy(d_gather_sum_x, gather_sum_x, num_devices * sizeof(double*), cudaMemcpyHostToDevice);
    cudaMemcpy(d_gather_sum_y, gather_sum_y, num_devices * sizeof(double*), cudaMemcpyHostToDevice);
    cudaMemcpy(d_gather_count, gather_count, num_devices * sizeof(int*), cudaMemcpyHostToDevice);


    printf("Executing k-means à %d iterations...\n", niters);
    double runtime = get_time();

    // Cannot be parallelized since it depends on the previous iteration
    for (int iter = 0; iter < niters; ++iter) {
        
        // Copy Data to each GPU and compute assignments
        #pragma omp parallel num_threads(num_devices)
        {
            int d = omp_get_thread_num();
            if (d < num_devices) {
                cudaSetDevice(d);
                
                // Set sum_0[x] = 0
                // Set sum_0[x] = 0
                // Set count[x] = 0
                cudaMemsetAsync(devices[d].sum_x, 0, k * sizeof(double), devices[d].stream);
                cudaMemsetAsync(devices[d].sum_y, 0, k * sizeof(double), devices[d].stream);
                cudaMemsetAsync(devices[d].count, 0, k * sizeof(int), devices[d].stream);
                
                // Use 256 Threads per block
                // divide the num of points with the number of threads to get the total number 
                // of blocks this computation runs on
                // 256 Threads per Streaming Multiprocessor supported on H100's
                // The GPU scheduler decides which blocks go to which SMs
                int NumberOfThreads = 256; 
                int NumberOfBlocks = std::ceil((double)devices[d].point_count / NumberOfThreads);
                determine_nearest_centroid<<<NumberOfBlocks, NumberOfThreads, 0, devices[d].stream>>>(
                    devices[d].point_count, k, 
                    devices[d].points_x, devices[d].points_y, 
                    devices[d].centroids_x, devices[d].centroids_y,
                    devices[d].sum_x, devices[d].sum_y, devices[d].count
                );
                cudaStreamSynchronize(devices[d].stream);

                // wait till each computation is done
                #pragma omp barrier
            }
        }
        
        // GATHER Phase: Send partial sums to GPU 0
        #pragma omp parallel num_threads(num_devices)
        {
             int d = omp_get_thread_num();
             if (d < num_devices) {
                 cudaSetDevice(d);
                 
                 if (d == 0) {
                     // Local copy on GPU 0
                     cudaMemcpyAsync(gather_sum_x[d], devices[d].sum_x, k*sizeof(double), cudaMemcpyDeviceToDevice, devices[d].stream);
                     cudaMemcpyAsync(gather_sum_y[d], devices[d].sum_y, k*sizeof(double), cudaMemcpyDeviceToDevice, devices[d].stream);
                     cudaMemcpyAsync(gather_count[d], devices[d].count, k*sizeof(int),    cudaMemcpyDeviceToDevice, devices[d].stream);
                 } else {
                     // P2P copy from GPU d to GPU 0
                     cudaMemcpyPeerAsync(gather_sum_x[d], 0, devices[d].sum_x, d, k*sizeof(double), devices[d].stream);
                     cudaMemcpyPeerAsync(gather_sum_y[d], 0, devices[d].sum_y, d, k*sizeof(double), devices[d].stream);
                     cudaMemcpyPeerAsync(gather_count[d], 0, devices[d].count, d, k*sizeof(int),    devices[d].stream);
                 }
                 cudaStreamSynchronize(devices[d].stream);
                 #pragma omp barrier
             }
        }

        // REDUCTION Phase: Compute new centroids on GPU 0
        // Use 256 Threads per block
        // divide the num of points with the number of threads to get the total number 
        // of blocks this computation runs on
        // 256 Threads per Streaming Multiprocessor supported on H100's
        // The GPU scheduler decides which blocks go to which SMs
        cudaSetDevice(0);
        int NumberOfThreads = 256;
        int NumberOfBlocks = std::ceil((double)k / NumberOfThreads);
        update_centroid_positions<<<NumberOfBlocks, NumberOfThreads, 0, devices[0].stream>>>(
            k, num_devices,
            d_gather_sum_x, d_gather_sum_y, d_gather_count,
            devices[0].centroids_x, devices[0].centroids_y
        );
        cudaStreamSynchronize(devices[0].stream);

        // BROADCAST Phase: Send new centroids to all other GPUs
        #pragma omp parallel num_threads(num_devices)
        {
             int d = omp_get_thread_num();
             if (d > 0 && d < num_devices) {
                 cudaSetDevice(d); 
                 cudaMemcpyPeerAsync(devices[d].centroids_x, d, devices[0].centroids_x, 0, k*sizeof(double), devices[d].stream);
                 cudaMemcpyPeerAsync(devices[d].centroids_y, d, devices[0].centroids_y, 0, k*sizeof(double), devices[d].stream);
                 cudaStreamSynchronize(devices[d].stream);
             }
        }

    }
    
    // Copy final centroids back to host
    cudaMemcpy(host_centroids_x.data(), devices[0].centroids_x, k*sizeof(double), cudaMemcpyDeviceToHost);
    cudaMemcpy(host_centroids_y.data(), devices[0].centroids_y, k*sizeof(double), cudaMemcpyDeviceToHost);

    // Save to memory history
    for(int j=0; j<k; ++j) {
        host_memory_x[niters * k + j] = host_centroids_x[j];
        host_memory_y[niters * k + j] = host_centroids_y[j];
    }

    runtime = get_time() - runtime;
    printf("Time Elapsed: %f s\n", runtime);
    write_memory("memory.out", niters, host_memory_x.data(), host_memory_y.data(), k);
    
    // Cleanup
    cudaFreeHost(pinned_points_x);
    cudaFreeHost(pinned_points_y);

    return EXIT_SUCCESS;
}
