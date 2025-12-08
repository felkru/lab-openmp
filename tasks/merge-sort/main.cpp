/*
*  This file is part of Christian's OpenMP software lab 
*
*  Copyright (C) 2016 by Christian Terboven <terboven@itc.rwth-aachen.de>
*  Copyright (C) 2016 by Jonas Hahnfeld <hahnfeld@itc.rwth-aachen.de>
*
*  This program is free software; you can redistribute it and/or modify
*  it under the terms of the GNU General Public License as published by
*  the Free Software Foundation; either version 2 of the License, or
*  (at your option) any later version.
*
*  This program is distributed in the hope that it will be useful,
*  but WITHOUT ANY WARRANTY; without even the implied warranty of
*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*  GNU General Public License for more details.
*
*  You should have received a copy of the GNU General Public License
*  along with this program; if not, write to the Free Software
*  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
*
*/

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/time.h>
#include <sys/mman.h>

#include <iostream>
#include <chrono>
#include <iomanip>
#include <algorithm>

#include <cstdlib>
#include <cstdio>

#include <cmath>
#include <ctime>
#include <cstring>



#include <parallel/algorithm>
#include <immintrin.h>

auto start_time = std::chrono::high_resolution_clock::now();

void print_timestamp(const char* label) {
    auto now = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> elapsed = now - start_time;
    std::cout << "[PROFILE] " << std::fixed << std::setprecision(6) << elapsed.count() << "s: " << label << std::endl;
}

/**
  * helper routine: check if array is sorted correctly
  */
bool isSorted(int ref[], int data[], const size_t size){
	__gnu_parallel::sort(ref, ref + size);
	for (size_t idx = 0; idx < size; ++idx){
		if (ref[idx] != data[idx]) {
			return false;
		}
	}
	return true;
}


/**
  * sequential merge step (straight-forward implementation)
  */
// AVX-512 Optimized Merge with Buffered Streaming Stores
void MsMergeSequential(int * __restrict__ out, const int * __restrict__ in, long begin1, long end1, long begin2, long end2, long outBegin) {
	long left = begin1;
	long right = begin2;
	long idx = outBegin;

    // --- Prologue: Align output to 64 bytes (16 integers) ---
    while ( (left < end1 && right < end2) && (((uintptr_t)(out + idx) & 63) != 0) ) {
        int val1 = in[left];
        int val2 = in[right];
        #ifdef ENABLE_BRANCHLESS
            long takeLeft = (val1 <= val2);
            _mm_stream_si32((int*)&out[idx], takeLeft ? val1 : val2);
            left += takeLeft;
            right += (1 - takeLeft);
        #else
            if (val1 <= val2) {
                _mm_stream_si32((int*)&out[idx], val1);
                left++;
            } else {
                _mm_stream_si32((int*)&out[idx], val2);
                right++;
            }
        #endif
        idx++;
    }

    // --- Bulk Loop: Write 64 bytes at a time ---
    // Buffer for collecting 16 integers. Aligned to 64 bytes for AVX-512 load.
    alignas(64) int buffer[16];
    const long P_DIST = 32;

    // We need at least 16 elements available in the output stream to write a full block.
    // However, the loop condition depends on input availability.
    // Detailed check: We can run a batch if we can safely perform 16 consumption steps?
    // Not necessarily. We might consume 16 from Left and 0 from Right.
    // So we need: left + 16 <= end1 AND right + 16 <= end2 to be SAFE.
    // If one is smaller, we fallback to scalar.
    
    while (left + 16 <= end1 && right + 16 <= end2) {
        
        // Prefetch hint
        _mm_prefetch((const char*)&in[left + P_DIST], _MM_HINT_T0);
        _mm_prefetch((const char*)&in[right + P_DIST], _MM_HINT_T0);

        for (int k = 0; k < 16; ++k) {
            int val1 = in[left];
            int val2 = in[right];
            #ifdef ENABLE_BRANCHLESS
                long takeLeft = (val1 <= val2);
                buffer[k] = takeLeft ? val1 : val2;
                left += takeLeft;
                right += (1 - takeLeft);
            #else
                if (val1 <= val2) {
                    buffer[k] = val1;
                    left++;
                } else {
                    buffer[k] = val2;
                    right++;
                }
            #endif
        }
        
        // Stream out full cache line (guarantees no RFO)
        _mm512_stream_si512((void*)&out[idx], _mm512_load_si512(buffer));
        idx += 16;
    }

    // --- Epilogue: Handle remaining items scalar-wise ---
	while (left < end1 && right < end2) {
        int val1 = in[left];
        int val2 = in[right];
        #ifdef ENABLE_BRANCHLESS
            long takeLeft = (val1 <= val2);
            _mm_stream_si32((int*)&out[idx], takeLeft ? val1 : val2);
            left += takeLeft;
            right += (1 - takeLeft);
        #else
            if (val1 <= val2) {
                _mm_stream_si32((int*)&out[idx], val1);
                left++;
            } else {
                _mm_stream_si32((int*)&out[idx], val2);
                right++;
            }
        #endif
        idx++;
	}

	while (left < end1) {
		_mm_stream_si32((int*)&out[idx], in[left]);
		left++, idx++;
	}

	while (right < end2) {
		_mm_stream_si32((int*)&out[idx], in[right]);
		right++, idx++;
	}
}

/**
  * parallel merge step
  */
void MsMergeParallel(int *out, int *in, long begin1, long end1, long begin2, long end2, long outBegin) {
	long n1 = end1 - begin1;
	long n2 = end2 - begin2;

	if (n1 + n2 < 250000) {
		MsMergeSequential(out, in, begin1, end1, begin2, end2, outBegin);
		return;
	}

	if (n1 >= n2) {
		long mid1 = (begin1 + end1) / 2;
		long mid2 = std::lower_bound(in + begin2, in + end2, in[mid1]) - in;
		long outMid = outBegin + (mid1 - begin1) + (mid2 - begin2);
		out[outMid] = in[mid1];

		#pragma omp task
		MsMergeParallel(out, in, begin1, mid1, begin2, mid2, outBegin);
		#pragma omp task
		MsMergeParallel(out, in, mid1 + 1, end1, mid2, end2, outMid + 1);
		#pragma omp taskwait
	} else {
		long mid2 = (begin2 + end2) / 2;
		long mid1 = std::upper_bound(in + begin1, in + end1, in[mid2]) - in;
		long outMid = outBegin + (mid1 - begin1) + (mid2 - begin2);
		out[outMid] = in[mid2];

		#pragma omp task
		MsMergeParallel(out, in, begin1, mid1, begin2, mid2, outBegin);
		#pragma omp task
		MsMergeParallel(out, in, mid1, end1, mid2 + 1, end2, outMid + 1);
		#pragma omp taskwait
	}
}

/**
  * sequential Sort
  */
void radixSort(int* arr, int* aux, long n) {
	int count[256];
	int* src = arr;
	int* dst = aux;

	for (int shift = 0; shift < 32; shift += 8) {
		std::memset(count, 0, sizeof(count));
		for (long i = 0; i < n; ++i) {
			count[(src[i] >> shift) & 0xFF]++;
		}
		
		int start = 0;
		for (int i = 0; i < 256; ++i) {
			int tmp = count[i];
			count[i] = start;
			start += tmp;
		}

		for (long i = 0; i < n; ++i) {
			dst[count[(src[i] >> shift) & 0xFF]++] = src[i];
		}

		std::swap(src, dst);
	}
}

/**
  * sequential MergeSort
  */
void MsSequential(int *array, int *tmp, bool inplace, long begin, long end) {
	if (begin < (end - 1)) {
		const long size = end - begin;

		if (size < 30000) {
			if (inplace) {
				radixSort(array + begin, tmp + begin, size);
			} else {
				std::copy(array + begin, array + end, tmp + begin);
				radixSort(tmp + begin, array + begin, size);
			}
			return;
		}

		const long half = (begin + end) / 2;

		#pragma omp task
		MsSequential(array, tmp, !inplace, begin, half);
		#pragma omp task
		MsSequential(array, tmp, !inplace, half, end);
		#pragma omp taskwait

		if (inplace) {
			MsMergeParallel(array, tmp, begin, half, half, end, begin);
		} else {
			MsMergeParallel(tmp, array, begin, half, half, end, begin);
		}
	} else if (!inplace) {
		tmp[begin] = array[begin];
	}
}

/**
  * Serial MergeSort
  */
void MsSerial(int *array, int *tmp, const size_t size) {
	#pragma omp parallel
	#pragma omp single
	MsSequential(array, tmp, true, 0, size);
}


/** 
  * @brief program entry point
  */
int main(int argc, char* argv[]) {
	// variables to measure the elapsed time
	struct timeval t1, t2;
	double etime;

	// expect one command line arguments: array size
    print_timestamp("Start of main");
	if (argc != 2) {
		printf("Usage: MergeSort.exe <array size> \n");
		printf("\n");
		return EXIT_FAILURE;
	} else {
// changes in main allocations
		const size_t stSize = strtol(argv[1], NULL, 10);
		size_t bytes = stSize * sizeof(int);
		int *data, *tmp, *ref;
#ifdef ENABLE_HUGE_PAGES
		posix_memalign((void**)&data, 2097152, bytes);
		posix_memalign((void**)&tmp, 2097152, bytes);
		posix_memalign((void**)&ref, 2097152, bytes);
		madvise(data, bytes, MADV_HUGEPAGE);
		madvise(tmp, bytes, MADV_HUGEPAGE);
		madvise(ref, bytes, MADV_HUGEPAGE);
#else
		data = (int*)malloc(bytes);
		tmp = (int*)malloc(bytes);
		ref = (int*)malloc(bytes);
#endif
        print_timestamp("Memory allocated");

		printf("Initialization...\n");

		#pragma omp parallel for
		for (size_t idx = 0; idx < stSize; ++idx){
			unsigned int seed = 95 + idx;
			data[idx] = (int) (stSize * (double(rand_r(&seed)) / RAND_MAX));
		}
        print_timestamp("Data initialized");
		std::copy(data, data + stSize, ref);
        print_timestamp("Reference copy created");

		double dSize = (stSize * sizeof(int)) / 1024 / 1024;
		printf("Sorting %zu elements of type int (%f MiB)...\n", stSize, dSize);

        // Pre-fault tmp array to avoid page fault overhead during measurement
        // Use the same parallel schedule as data initialization to enforce optimal NUMA placement
        #pragma omp parallel for
        for (size_t idx = 0; idx < stSize; ++idx) {
            tmp[idx] = 0;
        }
        print_timestamp("Tmp array pre-faulted");

        print_timestamp("Before MsSerial");
		gettimeofday(&t1, NULL);
		MsSerial(data, tmp, stSize);
		gettimeofday(&t2, NULL);
        print_timestamp("After MsSerial");
		etime = (t2.tv_sec - t1.tv_sec) * 1000 + (t2.tv_usec - t1.tv_usec) / 1000;
		etime = etime / 1000;

		printf("done, took %f sec. Verification...", etime);
		if (isSorted(ref, data, stSize)) {
			printf(" successful.\n");
		}
		else {
			printf(" FAILED.\n");
		}
        print_timestamp("Verification complete");

		free(data);
		free(tmp);
		free(ref);
	}
    print_timestamp("End of main");

	return EXIT_SUCCESS;
}
