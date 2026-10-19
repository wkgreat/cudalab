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

__device__ void swapInt(int &a, int &b) {
  int t = a;
  a = b;
  b = t;
}

__global__ void fillInt32Kernel(int *d_vals, int val, size_t n) {
  size_t i = blockDim.x * blockIdx.x + threadIdx.x;

  if (i >= n)
    return;

  d_vals[i] = val;
}

__global__ void cudaBitonicSortIntKernel(int *d_vals, size_t n, bool asc, int k,
                                         int j) {

  size_t i = blockDim.x * blockIdx.x + threadIdx.x;

  if (i >= n)
    return;

  int a = i ^ j;

  if (i < a) {
    bool up = ((i & k) == 0) == asc; // i%k==0 equalTo i/k%2==0
    if (up ? (d_vals[i] > d_vals[a]) : (d_vals[i] < d_vals[a])) {
      swapInt(d_vals[i], d_vals[a]);
    }
  }
}

cudaError_t cudaBitonicSortInt(int *h_vals, int *h_out, size_t n, bool asc) {

  size_t m = bitCeil(n);

  int numThreads = 256;
  int numBlocks = (numThreads + m - 1) / numThreads;

  int *d_vals;
  cudaMalloc(&d_vals, sizeof(int) * m);
  const int pad =
      asc ? std::numeric_limits<int>::max() : std::numeric_limits<int>::min();
  fillInt32Kernel<<<numBlocks, numThreads>>>(d_vals, pad, m);
  cudaMemcpy(d_vals, h_vals, n * sizeof(int), cudaMemcpyHostToDevice);

  for (int k = 2; k <= m; k <<= 1) {
    for (int j = k / 2; j > 0; j >>= 1) {
      cudaBitonicSortIntKernel<<<numBlocks, numThreads>>>(d_vals, m, asc, k, j);
    }
  }

  cudaMemcpy(h_out, d_vals, n * sizeof(int), cudaMemcpyDeviceToHost);
  cudaFree(d_vals);
  return cudaSuccess;
}

} // namespace cudalab