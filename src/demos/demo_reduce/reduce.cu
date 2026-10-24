#include "reduce.h"
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cub/cub.cuh>
#include <cub/device/device_segmented_reduce.cuh>
#include <cuda_device_runtime_api.h>
#include <cuda_runtime_api.h>
#include <driver_types.h>

namespace cudalab {

template <typename T> T min2(T a, T b) { return a < b ? a : b; }

struct IntSumOper {
  __device__ __forceinline__ int operator()(const int a, const int b) const {
    return a + b;
  }
};

cudaError_t cudaSumByCub(int *h_vals, size_t n, int *h_out) {

  int *d_vals;
  int *d_out;

  cudaMalloc(&d_vals, sizeof(int) * n);
  cudaMalloc(&d_out, sizeof(int));
  cudaMemcpy(d_vals, h_vals, sizeof(int) * n, cudaMemcpyHostToDevice);

  IntSumOper sumop;

  cudaError_t err = cub::DeviceReduce::Reduce(d_vals, d_out, n, sumop, 0);

  cudaMemcpy(h_out, d_out, sizeof(int), cudaMemcpyDeviceToHost);

  cudaFree(d_out);
  cudaFree(d_vals);

  return err;
}

struct Int4SumOper {
  __device__ __forceinline__ Int4 operator()(const Int4 &a,
                                             const Int4 &b) const {
    return {a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w};
  }
};

cudaError_t cudaSumByCub(Int4 *h_vals, size_t n, Int4 *h_out) {
  Int4 *d_vals;
  Int4 *d_out;

  cudaMalloc(&d_vals, sizeof(Int4) * n);
  cudaMalloc(&d_out, sizeof(Int4));
  cudaMemcpy(d_vals, h_vals, sizeof(Int4) * n, cudaMemcpyHostToDevice);

  Int4SumOper sumop;
  Int4 init{0, 0, 0, 0};

  cudaError_t err = cub::DeviceReduce::Reduce(d_vals, d_out, n, sumop, init);

  cudaMemcpy(h_out, d_out, sizeof(Int4), cudaMemcpyDeviceToHost);

  cudaFree(d_out);
  cudaFree(d_vals);

  return err;
}

cudaError_t cudaSegSumByCub(Int4 *h_vals, size_t stride, size_t n, Int4 *h_out,
                            size_t *h_nsegs) {

  std::int64_t nsegs = (n + stride - 1) / stride;

  Int4 *d_vals;
  Int4 *d_out;

  cudaMalloc(&d_vals, sizeof(Int4) * n);
  cudaMalloc(&d_out, sizeof(Int4) * nsegs);
  cudaMemcpy(d_vals, h_vals, sizeof(Int4) * n, cudaMemcpyHostToDevice);

  Int4SumOper sumop;
  Int4 init{0, 0, 0, 0};

  size_t *h_begin = (size_t *)malloc(sizeof(size_t) * nsegs);
  size_t *h_end = (size_t *)malloc(sizeof(size_t) * nsegs);
  for (size_t i = 0; i < nsegs; ++i) {
    h_begin[i] = stride * i;
    h_end[i] = min2(stride * (i + 1), n);
  }
  size_t *d_begin;
  size_t *d_end;
  cudaMalloc(&d_begin, sizeof(size_t) * nsegs);
  cudaMalloc(&d_end, sizeof(size_t) * nsegs);
  cudaMemcpy(d_begin, h_begin, sizeof(size_t) * nsegs, cudaMemcpyHostToDevice);
  cudaMemcpy(d_end, h_end, sizeof(size_t) * nsegs, cudaMemcpyHostToDevice);

  cudaError_t err = cub::DeviceSegmentedReduce::Reduce(
      d_vals, d_out, nsegs, d_begin, d_end, sumop, init);

  cudaMemcpy(h_out, d_out, sizeof(Int4) * nsegs, cudaMemcpyDeviceToHost);
  *h_nsegs = nsegs;

  cudaFree(d_out);
  cudaFree(d_vals);

  return err;
}

} // namespace cudalab