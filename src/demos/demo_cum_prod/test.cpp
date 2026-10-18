#include <catch2/benchmark/catch_benchmark.hpp>
#include <catch2/catch_test_macros.hpp>
#include <catch2/generators/catch_generators.hpp>
#include <catch2/matchers/catch_matchers_floating_point.hpp>
#include <cstdlib>

#include "catch2/matchers/catch_matchers.hpp"
#include "common/random.h"
#include "cum_prod.h"

TEST_CASE("cuda cum prod", "[cuda][cum_prod]") {

  size_t n = 102400;

  float *h_vals = cudalab::common::randomFloat(n, 0, 5);

  float *h_rets = (float *)malloc(sizeof(float) * n);

  int err = cudalab::cudaCumProd3Phase(h_vals, h_rets, n);

  REQUIRE(err == 0);

  float cp = 1.0;

  for (int i = 0; i < n; ++i) {
    cp *= h_vals[i];
    REQUIRE_THAT(h_rets[i], Catch::Matchers::WithinAbs(cp, 1E-6));
  }

  free(h_vals);
  free(h_rets);
}