#include "bitonic_sort.h"
#include "common/random.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>

int main() {

  int n = 1024;
  int nMismatch = 0;

  int *h_vals = cudalab::common::randomInt(n);

  cudalab::cudaBitonicSortInt(h_vals, n, true);

  for (int i = 1; i < n; ++i) {
    if (h_vals[i] < h_vals[i - 1]) {
      nMismatch++;
    }
  }

  std::free(h_vals);

  if (nMismatch > 0) {
    std::printf("cudaBitonicSortInt error, num of mismatch=%d\n", nMismatch);
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}