// C header
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

// utility header
// This file is assumed to define:
// - ooo_options, ooo_input, timespan structures
// - parseCmdLine()
// - loadInputFile_4SMXV()
// - print_error_check()
// - print_performance_results()
#include "ooo_cmdline.h"

void spmxv(ooo_options *tOptions, ooo_input *tInput)
{
    int iNumRepetitions = tOptions->iNumRepetitions; // set with -r <numrep>

    // setup data structures with aligned allocation for better vectorization
    double *y = (double*) aligned_alloc(64, sizeof(double) * (tInput->stNumRows)); // result
    double *Aval = (double*) aligned_alloc(64, sizeof(double) * (tInput->stNumNonzeros)); // values
    int    *Acol = (int*) aligned_alloc(64, sizeof(int) * (tInput->stNumNonzeros)); // column indices
    int    *Arow = (int*) aligned_alloc(64, sizeof(int) * (tInput->stNumRows + 1)); // begin of each row
    double *x = (double*) aligned_alloc(64, sizeof(double) * (tInput->stNumRows)); // RHS

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

        double * __restrict__ y_ptr = y;
        const double * __restrict__ Aval_ptr = Aval;
        const int * __restrict__ Acol_ptr = Acol;
        const int * __restrict__ Arow_ptr = Arow;
        const double * __restrict__ x_ptr = x;

        #pragma omp teams distribute parallel for schedule(guided, 64)
        for (i = 0; i < tInput->stNumRows; i++)
        {
            const int rowbeg = Arow_ptr[i];
            const int rowend = Arow_ptr[i+1];
            double sum = 0.0;
            
            #pragma omp simd reduction(+:sum)
            for (int j = rowbeg; j < rowend; j++)
            {
                sum += Aval_ptr[j] * x_ptr[Acol_ptr[j]];
            }

            y_ptr[i] = sum;
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
    free(y);
    free(Aval);
    free(Acol);
    free(Arow);
    free(x);
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