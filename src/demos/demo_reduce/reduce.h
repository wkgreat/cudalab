#pragma once

#include <cuda_runtime.h>
#include <driver_types.h>

namespace cudalab {

struct Int4 {
  int x;
  int y;
  int z;
  int w;
};

cudaError_t cudaSumByCub(int *h_vals, size_t n, int *h_out);

cudaError_t cudaSumByCub(Int4 *h_vals, size_t n, Int4 *h_out);

cudaError_t cudaSegSumByCub(Int4 *h_vals, size_t stride, size_t n, Int4 *h_out,
                            size_t *h_nsegs);

} // namespace cudalab