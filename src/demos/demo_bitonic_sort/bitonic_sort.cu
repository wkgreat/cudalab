#include "bitonic_sort.h"
#include <algorithm>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <driver_types.h>
#include <limits>

namespace cudalab {

__host__ __device__ static size_t bitCeil(size_t n) {
  if (n <= 1) {
    return 1;
  }
  n--;
  n |= n >> 1;
  n |= n >> 2;
  n |= n >> 4;
  n |= n >> 8;
  n |= n >> 16;
  return n + 1;
}

__host__ static int *padpow2(int *h_vals, int n, bool asc, size_t &m) {
  m = bitCeil(n);
  int *r = (int *)std::malloc(sizeof(int) * m);
  int pad =
      asc ? std::numeric_limits<int>::max() : std::numeric_limits<int>::min();
  std::fill(r, r + m, pad);
  std::memcpy(r, h_vals, sizeof(int) * n);
  return r;
};

int bitonicSortInt(int *h_vals, int *h_out, size_t n, bool asc) {

  size_t m;
  int *h_padVals = padpow2(h_vals, n, asc, m);

  for (int k = 2; k <= m; k <<= 1) {
    for (int j = k / 2; j > 0; j >>= 1) {
      for (int i = 0; i < m; ++i) {
        int a = i ^ j;
        if (i < a) {
          const bool up = ((i & k) == 0) == asc; // i%k==0 equalTo i/k%2==0
          if (up ? (h_padVals[i] > h_padVals[a])
                 : (h_padVals[i] < h_padVals[a])) {
            std::swap(h_padVals[i], h_padVals[a]);
          }
        }
      }
    }
  }

  std::memcpy(h_out, h_padVals, sizeof(int) * n);
  std::free(h_padVals);

  return 0;
}

cudaError_t cudaBitonicSortInt(int *h_vals, int *h_out, size_t n, bool asc) {
  // TODO
  return cudaSuccess;
}

} // namespace cudalab