#include "bitonic_sort.h"
#include <cstddef>
#include <driver_types.h>

namespace cudalab {

static size_t bitCeil(size_t n) {
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

cudaError_t cudaBitonicSortInt(int *h_vals, size_t n, bool asc) {

  int m = bitCeil(n);

  // TODO

  return cudaSuccess;
}

} // namespace cudalab