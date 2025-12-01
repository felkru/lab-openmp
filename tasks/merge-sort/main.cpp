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

#include <iostream>
#include <algorithm>

#include <cstdlib>
#include <cstdio>

#include <cmath>
#include <ctime>
#include <cstring>



/**
  * helper routine: check if array is sorted correctly
  */
bool isSorted(int ref[], int data[], const size_t size){
	std::sort(ref, ref + size);
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
void MsMergeSequential(int *out, int *in, long begin1, long end1, long begin2, long end2, long outBegin) {
	long left = begin1;
	long right = begin2;

	long idx = outBegin;

	while (left < end1 && right < end2) {
		if (in[left] <= in[right]) {
			out[idx] = in[left];
			left++;
		} else {
			out[idx] = in[right];
			right++;
		}
		idx++;
	}

	while (left < end1) {
		out[idx] = in[left];
		left++, idx++;
	}

	while (right < end2) {
		out[idx] = in[right];
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
  * sequential MergeSort
  */
void MsSequential(int *array, int *tmp, bool inplace, long begin, long end) {
	if (begin < (end - 1)) {
		const long half = (begin + end) / 2;
		const long size = end - begin;

		if (size >= 30000) { // task overhead is not worth it for small tasks
			#pragma omp task
			MsSequential(array, tmp, !inplace, begin, half);
			#pragma omp task
			MsSequential(array, tmp, !inplace, half, end);
			#pragma omp taskwait
		} else {
			MsSequential(array, tmp, !inplace, begin, half);
			MsSequential(array, tmp, !inplace, half, end);
		}

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
	if (argc != 2) {
		printf("Usage: MergeSort.exe <array size> \n");
		printf("\n");
		return EXIT_FAILURE;
	} else {
		const size_t stSize = strtol(argv[1], NULL, 10);
		int *data = (int*) malloc(stSize * sizeof(int));
		int *tmp = (int*) malloc(stSize * sizeof(int));
		int *ref = (int*) malloc(stSize * sizeof(int));

		printf("Initialization...\n");

		srand(95);
		for (size_t idx = 0; idx < stSize; ++idx){
			data[idx] = (int) (stSize * (double(rand()) / RAND_MAX));
		}
		std::copy(data, data + stSize, ref);

		double dSize = (stSize * sizeof(int)) / 1024 / 1024;
		printf("Sorting %zu elements of type int (%f MiB)...\n", stSize, dSize);

		gettimeofday(&t1, NULL);
		MsSerial(data, tmp, stSize);
		gettimeofday(&t2, NULL);
		etime = (t2.tv_sec - t1.tv_sec) * 1000 + (t2.tv_usec - t1.tv_usec) / 1000;
		etime = etime / 1000;

		printf("done, took %f sec. Verification...", etime);
		if (isSorted(ref, data, stSize)) {
			printf(" successful.\n");
		}
		else {
			printf(" FAILED.\n");
		}

		free(data);
		free(tmp);
		free(ref);
	}

	return EXIT_SUCCESS;
}
