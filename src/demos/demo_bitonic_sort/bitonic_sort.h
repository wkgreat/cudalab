#pragma once

#include <cstddef>
#include <cuda_runtime.h>

namespace cudalab {

cudaError_t cudaBitonicSortInt(int *h_vals, int *h_out, size_t n,
                               bool asc = true);
int bitonicSortInt(int *h_vals, int *h_out, size_t n, bool asc = true);

} // namespace cudalab