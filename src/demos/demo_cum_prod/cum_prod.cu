#include "cum_prod.h"
#include <cub/cub.cuh>
#include <cub/device/device_scan.cuh>
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

__global__ void cudaCumProd3PhaseKernel2(float *d_cache, size_t nBlocks) {
  for (int i = 1; i < nBlocks; ++i) {
    d_cache[i] *= d_cache[i - 1];
  }
}

__global__ void cudaCumProd3PhaseKernel3(float *d_cache, float *d_rets,
                                         size_t N) {
  unsigned int k = blockDim.x * blockIdx.x + threadIdx.x;
  if (blockIdx.x > 0 && k < N) {
    d_rets[k] *= d_cache[blockIdx.x - 1];
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
  cudaMalloc(&d_rets, sizeof(float) * N);
  cudaCumProd3PhaseKernel1<<<blockNum, blockDim, sharedSize>>>(d_vals, d_cache,
                                                               d_rets, N);
  cudaCumProd3PhaseKernel2<<<1, 1>>>(d_cache, blockNum);

  cudaCumProd3PhaseKernel3<<<blockNum, blockDim>>>(d_cache, d_rets, N);

  cudaMemcpy(h_rets, d_rets, sizeof(float) * N, cudaMemcpyDeviceToHost);

  cudaFree(d_vals);
  cudaFree(d_cache);
  cudaFree(d_rets);

  return 0;
}

int cudaCumProd1Phase(float *h_vals, float *h_rets, size_t N) {
  // TODO
  return 1;
}

struct MultiplyOp {
  __device__ float operator()(float a, float b) const { return a * b; }
};

int cudaCumProdByCub(float *h_vals, float *h_rets, size_t N) {

  size_t temp_bytes = 0;
  MultiplyOp mult_op;

  float *d_vals, *d_rets;

  cudaMalloc(&d_vals, sizeof(float) * N);
  cudaMemcpy(d_vals, h_vals, sizeof(float) * N, cudaMemcpyHostToDevice);
  cudaMalloc(&d_rets, sizeof(float) * N);

  cub::DeviceScan::InclusiveScan(nullptr, temp_bytes, d_vals, d_rets, mult_op,
                                 N);

  void *d_temps;
  cudaMalloc(&d_temps, temp_bytes);

  cub::DeviceScan::InclusiveScan(d_temps, temp_bytes, d_vals, d_rets, mult_op,
                                 N);

  cudaMemcpy(h_rets, d_rets, sizeof(float) * N, cudaMemcpyDeviceToHost);

  cudaFree(d_temps);
  cudaFree(d_vals);
  cudaFree(d_rets);

  return 0;
}

} // namespace cudalab