
#include <immintrin.h>

// Optimized implementation of MsMergeSequential
// Features:
// 1. Streaming Stores (_mm_stream_si32) to avoid RFO.
// 2. Software Prefetching to hide latency.
// 3. Loop Unrolling (8x) to reduce loop overhead.

void MsMergeSequential_Opt(int * __restrict__ out, const int * __restrict__ in, long begin1, long end1, long begin2, long end2, long outBegin) {
	long left = begin1;
	long right = begin2;
	long idx = outBegin;
    
    // Prefetch distance (experimental, tune based on hardware)
    // 64 bytes = 16 ints. 
    // Prefetch ahead by ~20-50 cache lines?
    const long P_DIST = 64; 

	while (left < end1 && right < end2) {
        // Simple unrolling? 
        // We can't easily unroll the "decision" because it depends on previous state (left/right increments).
        // However, we can unroll the check "left < end1 && right < end2" by checking "left + 8 < end1 && right + 8 < end2"
        // provided we have a fallback.
        
        // But since we don't know how many we take from left vs right, we can't safely access left+8 if we only take 1.
        // Wait, "Safe Unrolling" for merge is hard without sentinel.
        // But we can just unroll the BODY 4-8 times with checks? No, that spills registers.
        
        // Better approach: "Blocked" check.
        // If (left + 8 < end1) and (right + 8 < end2), we can safely do 8 steps without bounds check?
        // Yes!
        
        if (left + 8 < end1 && right + 8 < end2) {
            // Unroll 8 times
            for (int k = 0; k < 8; ++k) {
                int val1 = in[left];
                int val2 = in[right];
                
                // Prefetch
                if ((idx & 15) == 0) { // Every 16 writes (64 bytes)
                    _mm_prefetch((const char*)&in[left + P_DIST], _MM_HINT_T0);
                    _mm_prefetch((const char*)&in[right + P_DIST], _MM_HINT_T0);
                    // Also prefetch output? No, streaming stores don't need prefetch (they invalidate).
                }

                #ifdef ENABLE_BRANCHLESS
                    long takeLeft = (val1 <= val2);
                     _mm_stream_si32((int*)&out[idx], takeLeft ? val1 : val2);
                    left += takeLeft;
                    right += (1 - takeLeft);
                    idx++;
                #else
                    if (val1 <= val2) {
                         _mm_stream_si32((int*)&out[idx], val1);
                        left++;
                    } else {
                         _mm_stream_si32((int*)&out[idx], val2);
                        right++;
                    }
                    idx++;
                #endif
            }
        } else {
            // Fallback for boundary
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
