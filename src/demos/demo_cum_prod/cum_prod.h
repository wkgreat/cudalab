#pragma once

namespace cudalab {

inline int cumprod(float *h_vals, float *h_rets, size_t N) {
  h_rets[0] = h_vals[0];
  for (int i = 1; i < N; ++i) {
    h_rets[i] = h_vals[i] * h_rets[i - 1];
  }
  return 0;
}

int cudaCumProd3Phase(float *h_vals, float *h_rets, size_t N);

// algorithm of cub
int cudaCumProd1Phase(float *h_vals, float *h_rets, size_t N);

// invoke scan of Cub lib
int cudaCumProdByCub(float *h_vals, float *h_rets, size_t N);

// cub::DeviceSegmentedScan
int cudaSegCumProdByCub(float *h_vals, float *h_rets, size_t stride, size_t n,
                        bool exlusive);

} // namespace cudalab