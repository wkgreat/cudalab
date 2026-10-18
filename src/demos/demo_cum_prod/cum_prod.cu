#include "cum_prod.h"
#include <__clang_cuda_builtin_vars.h>
#include <__clang_cuda_runtime_wrapper.h>
#include <cuda_device_runtime_api.h>
#include <cuda_runtime.h>
#include <cuda_runtime_api.h>
#include <driver_types.h>

namespace cudalab {

#define BLOCKDIM 256

__global__ void cudaCumProd3PhaseKernel1(float *d_vals, float *d_cache,
                                         float *d_rets, size_t N) {
  __shared__ float s_vals[BLOCKDIM];
  unsigned int k = blockDim.x * blockIdx.x + threadIdx.x;
  s_vals[threadIdx.x] = k < N ? d_vals[k] : 1.0f;
  __syncthreads();

  float cp = 1.0;
  for (unsigned int i = 0; i <= threadIdx.x; ++i) {
    cp *= s_vals[i];
  }
  if (k < N) {
    d_rets[k] = cp;
  }
  if (threadIdx.x == blockDim.x - 1) {
    d_cache[blockIdx.x] = cp;
  }
}

int cudaCumProd3Phase(float *h_vals, float *h_rets, size_t N) {

  size_t blockDim = BLOCKDIM;
  size_t blockNum = (blockDim + N - 1) / blockDim;
  size_t sharedSize = blockDim * sizeof(float);

  float *d_vals, *d_cache, *d_rets;
  cudaMalloc(&d_vals, sizeof(float) * N);
  cudaMemcpy(d_vals, h_vals, sizeof(float) * N, cudaMemcpyHostToDevice);
  cudaMalloc(&d_cache, sizeof(float) * blockNum);
  cudaCumProd3PhaseKernel1<<<blockNum, blockDim, sharedSize>>>(d_vals, d_cache,
                                                               d_rets, N);
  // TODO
  return 0;
}

int cudaCumProd1Phase(float *h_vals, float *h_rets, size_t N) { return 1; }

} // namespace cudalab