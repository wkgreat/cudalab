#pragma one

#include <cstddef>
#include <cuda_runtime.h>

namespace cudalab {

cudaError_t cudaBitonicSortInt(int *h_vals, size_t n, bool asc = true);

}