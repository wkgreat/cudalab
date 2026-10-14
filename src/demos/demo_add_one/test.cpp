#include <catch2/benchmark/catch_benchmark.hpp>
#include <catch2/catch_test_macros.hpp>
#include <catch2/generators/catch_generators.hpp>
#include <cstdlib>
#include <cstring>

#include "common/random.h"
#include "ocl_add_one.h"

TEST_CASE("opencl add one", "[opencl][add_one]") {

  int n = 100000;

  int *h_vals0 = cudalab::common::randomInt(n, 0, 1000);

  int *h_vals1 = (int *)malloc(sizeof(int) * n);
  memcpy(h_vals1, h_vals0, sizeof(int) * n);

  cudalab::ocl::oclAddOne(h_vals1, n);

  for (int i = 0; i < n; ++i) {
    int d = h_vals1[i] - h_vals0[i];
    REQUIRE(d == 1);
  }
}