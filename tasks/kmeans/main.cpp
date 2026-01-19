#include <string>
#include <fstream>
#include <cstdlib>
#include <cstdio>
#include <cmath>
#include <cfloat>
#include <sys/time.h>

#include <omp.h>

#define DEFAULT_K 5
#define DEFAULT_NITERS 20

struct point_t {
    double x;
    double y;
};

double get_time() {
    struct timeval tv;
    gettimeofday(&tv, (struct timezone*)0);
    return ((double)tv.tv_sec + (double)tv.tv_usec / 1000000.0 );
}

void read_points(std::string filename, point_t* p, int n){
    std::ifstream infile{filename};
    double x, y;
    int i = 0;
    while (infile >> x >> y) {
        if (i >= n) {
            printf("WARNING: more points in input file '%s' than read: stopping after %d lines\n", filename.c_str(), i);
            return;
        }
        p[i].x = x;
        p[i].y = y;
        i++;
    }
}

void write_memory(std::string filename, int niters, point_t* memory, int k){
    std::ofstream outfile{filename};
    for (int iter = 0; iter < niters + 1; ++iter) {
        for (int i = 0; i < k; ++i) {
            outfile << iter << ' ' << memory[iter * k + i].x << ' ' << memory[iter * k + i].y << '\n';
        }
    }
}

void init_centroids(point_t *centroids, int k, int d){
    for (int i = 0; i < k; ++i) {
        centroids[i].x = rand() % d;
        centroids[i].y = rand() % d;
    }
}

void k_means(int niters, point_t *points, point_t *centroids, int *assignment, point_t* memory, int n, int k, int prune_start_iter) {
    // Allocate auxiliary arrays for reduction
    double* sum_x = (double*) malloc(k * sizeof(double));
    double* sum_y = (double*) malloc(k * sizeof(double));
    int* count = (int*) malloc(k * sizeof(int));

    // Elkan's/Hamerly's Optimization Structures
    double* upper_bound = (double*) malloc(n * sizeof(double));
    double* lower_bound = (double*) malloc(k * sizeof(double)); // Half-distance to nearest other center
    double* drift = (double*) malloc(k * sizeof(double));

    // Initialize upper bounds to infinity
    for (int i = 0; i < n; ++i) upper_bound[i] = DBL_MAX;
    for (int j = 0; j < k; ++j) drift[j] = 0.0;

    #pragma omp target data map(to: points[0:n]) \
                            map(tofrom: centroids[0:k], memory[0:(niters + 1) * k], upper_bound[0:n]) \
                            map(alloc: assignment[0:n], sum_x[0:k], sum_y[0:k], count[0:k], lower_bound[0:k], drift[0:k])
    {
        for (int iter = 0; iter < niters; ++iter) {
            
            bool pruning_active = (iter >= prune_start_iter);

            // Step 0: Compute Lower Bounds for Centroids (O(K^2))
            if (pruning_active) {
                #pragma omp target teams distribute parallel for collapse(1)
                for (int j = 0; j < k; ++j) {
                    double min_dist_sq = DBL_MAX;
                    for (int l = 0; l < k; ++l) {
                        if (j == l) continue;
                        double d_sq = (centroids[j].x - centroids[l].x) * (centroids[j].x - centroids[l].x) +
                                      (centroids[j].y - centroids[l].y) * (centroids[j].y - centroids[l].y);
                        if (d_sq < min_dist_sq) min_dist_sq = d_sq;
                    }
                    lower_bound[j] = std::sqrt(min_dist_sq) * 0.5;
                }
            }

            // Step 1: Assignment with Pruning
            #pragma omp target teams distribute parallel for
            for (int i = 0; i < n; ++i) {
                // Update upper bound with drift 
                if (pruning_active && iter > 0) {
                   upper_bound[i] += drift[assignment[i]];
                }

                // Pruning Condition
                if (pruning_active && iter > 0) {
                    if (upper_bound[i] <= lower_bound[assignment[i]]) {
                        continue; // Pruned!
                    }
                }

                double optimal_dist_sq = DBL_MAX;
                int best_cluster = 0;
                
                for (int j = 0; j < k; ++j) {
                    double dist_sq = (points[i].x - centroids[j].x) * (points[i].x - centroids[j].x) +
                                     (points[i].y - centroids[j].y) * (points[i].y - centroids[j].y);
                    if (dist_sq < optimal_dist_sq) {
                        optimal_dist_sq = dist_sq;
                        best_cluster = j;
                    }
                }
                assignment[i] = best_cluster;
                
                // Store Euclidean distance if pruning is/will be active
                if (pruning_active) {
                    upper_bound[i] = std::sqrt(optimal_dist_sq);
                }
            }

            // Step 2: Reset Sums
            #pragma omp target teams distribute parallel for
            for (int j = 0; j < k; ++j) {
                sum_x[j] = 0.0;
                sum_y[j] = 0.0;
                count[j] = 0;
            }

            // Step 3: Accumulate (Global Atomics)
            #pragma omp target teams distribute parallel for
            for (int i = 0; i < n; ++i) {
                int j = assignment[i];
                #pragma omp atomic update
                sum_x[j] += points[i].x;
                #pragma omp atomic update
                sum_y[j] += points[i].y;
                #pragma omp atomic update
                count[j] += 1;
            }

            // Step 4: Update Centroids & Compute Drift
            #pragma omp target teams distribute parallel for
            for (int j = 0; j < k; ++j) {
                drift[j] = 0.0;
                if (count[j] != 0) {
                    double new_x = sum_x[j] / count[j];
                    double new_y = sum_y[j] / count[j];
                    
                    if (pruning_active) {
                        double dx = new_x - centroids[j].x;
                        double dy = new_y - centroids[j].y;
                        drift[j] = std::sqrt(dx*dx + dy*dy);
                    }
                    
                    centroids[j].x = new_x;
                    centroids[j].y = new_y;
                }
                // save centroids to memory
                memory[(iter + 1) * k + j].x = centroids[j].x;
                memory[(iter + 1) * k + j].y = centroids[j].y;
            }
        }
    }
    free(sum_x);
    free(sum_y);
    free(count);
    free(upper_bound);
    free(lower_bound);
    free(drift);
}

int main(int argc, const char* argv[]) {
    srand(1234);
    if (argc < 4 || argc > 7) {
        printf("Usage: %s <input file> <size dimensions> <num points> <num centroids> <num iters> [prune_start_iter]\n", argv[0]);
        return EXIT_FAILURE;
    }

    const int dim = atoi(argv[2]);
    const char * input_file = argv[1];
    const int n = atoi(argv[3]);
    const int k = (argc > 4 ? atoi(argv[4]) : DEFAULT_K);
    const int niters = (argc > 5 ? atoi(argv[5]) : DEFAULT_NITERS);
    const int prune_start_iter = (argc > 6 ? atoi(argv[6]) : 0);

    point_t * points = (point_t*) malloc(n * sizeof(point_t));
    point_t * centroids = (point_t*) malloc(k * sizeof(point_t));
    int * assignment = (int*) malloc(n * sizeof(int));
    // reserve extra space to save the initial centroid placement
    point_t * memory = (point_t*) malloc((niters + 1) * k * sizeof(point_t));

    read_points(input_file, points, n);
    init_centroids(centroids, k, dim);
    for (int j = 0; j < k; ++j) {
        memory[j].x = centroids[j].x;
        memory[j].y = centroids[j].y;
    }

    printf("Executing k-means à %d iterations with %d points and %d centroids (Pruning start: %d)...\n", niters, n, k, prune_start_iter);
    double runtime = get_time();
    k_means(niters, points, centroids, assignment, memory, n, k, prune_start_iter);
    runtime = get_time() - runtime;

    printf("Time Elapsed: %f s\n", runtime);

    write_memory("memory.out", niters, memory, k);

    free(assignment);
    free(centroids);
    free(points);
    free(memory);

    return EXIT_SUCCESS;
}
