#include "bitonic_sort.h"
#include "common/perf.h"
#include "common/random.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>

int test_bitonicSortInt() {

  int n = 1024000;
  int nMismatch = 0;

  int *h_vals = cudalab::common::randomInt(n);

  cudalab::bitonicSortInt(h_vals, h_vals, n, true);

  for (int i = 1; i < n; ++i) {
    if (h_vals[i] < h_vals[i - 1]) {
      nMismatch++;
    }
  }

  std::free(h_vals);

  if (nMismatch > 0) {
    std::printf("bitonicSortInt error, num of mismatch=%d\n", nMismatch);
    return EXIT_FAILURE;
  } else {
    std::printf("bitonicSortInt pass.\n");
  }

  return EXIT_SUCCESS;
}

int test_cudaBitonicSortInt() {

  int n = 1024000;
  int nMismatch = 0;

  int *h_vals = cudalab::common::randomInt(n);

  cudalab::cudaBitonicSortInt(h_vals, h_vals, n, true);

  for (int i = 1; i < n; ++i) {
    if (h_vals[i] < h_vals[i - 1]) {
      nMismatch++;
    }
  }

  std::free(h_vals);

  if (nMismatch > 0) {
    std::printf("cudaBitonicSortInt error, num of mismatch=%d\n", nMismatch);
    return EXIT_FAILURE;
  } else {
    std::printf("cudaBitonicSortInt pass.\n");
  }

  return EXIT_SUCCESS;
}

int main() {

  cudalab::perf::Clock clock;
  clock.start();
  test_bitonicSortInt();
  clock.stop();
  auto dur0 = clock.duration().count();

  clock.start();
  test_cudaBitonicSortInt();
  clock.stop();
  auto dur1 = clock.duration().count();

  printf("test_bitonicSortInt\tTime=%ld\n", dur0);
  printf("test_cudaBitonicSortInt\tTime=%ld\n", dur1);

  return EXIT_SUCCESS;
}