// C header
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#include <numa.h>

#include "ooo_cmdline.h"

void spmxv(ooo_options *tOptions, ooo_input *tInput)
{
    int iNumRepetitions = tOptions->iNumRepetitions; // set with -r <numrep>

    size_t y_size = sizeof(double) * (tInput->stNumRows);
    size_t Aval_size = sizeof(double) * (tInput->stNumNonzeros);
    size_t Acol_size = sizeof(int) * (tInput->stNumNonzeros);
    size_t Arow_size = sizeof(int) * (tInput->stNumRows + 1);
    size_t x_size = sizeof(double) * (tInput->stNumRows);
    size_t timings_size = sizeof(timespan) * iNumRepetitions;

    double * __restrict__ y = (double*) numa_alloc_interleaved(y_size);
    double * __restrict__ Aval = (double*) numa_alloc_interleaved(Aval_size);
    int    * __restrict__ Acol = (int*) numa_alloc_interleaved(Acol_size);
    int    * __restrict__ Arow = (int*) numa_alloc_interleaved(Arow_size);
    double * __restrict__ x = (double*) numa_alloc_interleaved(x_size);

    // allocate helper data
    timespan *timings = (timespan*) malloc(sizeof(timespan) * iNumRepetitions);
    double t1, t2;

    int i, rep;
    #pragma omp parallel
    {
        #pragma omp for schedule(static)
        for (i = 0; i < tInput->stNumRows; i++)
        {
            Arow[i] = tInput->row[i];
            y[i] = 0.0;
            x[i] = 1;
        }

        #pragma omp single
        Arow[tInput->stNumRows] = tInput->stNumNonzeros;

        #pragma omp for schedule(static)
        for (i = 0; i < tInput->stNumRows; i++)
        {
            int rowbeg = Arow[i];
            int rowend = Arow[i+1];
            int nz;
            for (nz = rowbeg; nz < rowend; nz++)
            {
                Aval[nz] = tInput->val[nz];
                Acol[nz] = tInput->col[nz];
            }
        }
    }

    // take the time: start
    t1 = omp_get_wtime();

    for (rep = 0; rep < iNumRepetitions; rep++)
    {
        timings[rep].dBegin = omp_get_wtime();

        #pragma omp teams distribute parallel for schedule(dynamic, 1) proc_bind(spread)
        for (i = 0; i < tInput->stNumRows; i++)
        {
            double sum = 0.0;

            #pragma omp simd reduction(+:sum)
            for (int j = Arow[i]; j < Arow[i+1]; j++)
            {
                sum += Aval[j] * x[Acol[j]];
            }

            y[i] = sum;
        }

        timings[rep].dEnd = omp_get_wtime();
    }

    // take the time: end
    t2 = omp_get_wtime();

    // error check
    print_error_check(y, tInput);

    // process_results
    print_performance_results(tOptions, t1, t2, timings, tInput);

    // cleanup
    numa_free(y, y_size);
    numa_free(Aval, Aval_size);
    numa_free(Acol, Acol_size);
    numa_free(Arow, Arow_size);
    numa_free(x, x_size);
    numa_free(timings, timings_size);
    free(timings);

} // end loop

int main(int argc, char* argv[])
{
    // parse command line
    ooo_options tOptions;
    if (! parseCmdLine(&tOptions, argc, argv))
    {
        return EXIT_FAILURE;
    }

    // load filename
    ooo_input tInput;
    if (! loadInputFile_4SMXV(&tOptions, &tInput))
    {
        return EXIT_FAILURE;
    }

    // SpMXV-Kernel
    spmxv(&tOptions, &tInput);

    return EXIT_SUCCESS;
}
