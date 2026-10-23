#include <catch2/benchmark/catch_benchmark.hpp>
#include <catch2/catch_test_macros.hpp>
#include <catch2/generators/catch_generators.hpp>
#include <catch2/matchers/catch_matchers_floating_point.hpp>
#include <cstdio>
#include <cstdlib>
#include <fmt/format.h>

#include "catch2/matchers/catch_matchers.hpp"
#include "common/random.h"
#include "cum_prod.h"

TEST_CASE("cum prod", "[cpu][cum_prod]") {

  size_t n = 102400;

  float *h_vals = cudalab::common::randomFloat(n, 0, 5);

  float *h_rets = (float *)malloc(sizeof(float) * n);

  int err = cudalab::cumprod(h_vals, h_rets, n);

  REQUIRE(err == 0);

  float cp = 1.0;

  for (int i = 0; i < n; ++i) {
    cp *= h_vals[i];
    REQUIRE_THAT(h_rets[i], Catch::Matchers::WithinAbs(cp, 1E-6));
  }

  free(h_vals);
  free(h_rets);
}

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

TEST_CASE("cuda cum prod by cub", "[cuda][cum_prod]") {

  size_t n = 10;

  float *h_vals = cudalab::common::randomFloat(n, 0, 10);

  float *h_rets = (float *)malloc(sizeof(float) * n);

  int err = cudalab::cudaCumProdByCub(h_vals, h_rets, n);

  REQUIRE(err == 0);

  float cp = 1.0;

  for (int i = 0; i < n; ++i) {
    cp *= h_vals[i];
    REQUIRE_THAT(h_rets[i], Catch::Matchers::WithinAbs(cp, 1E-6));
  }

  free(h_vals);
  free(h_rets);
}

TEST_CASE("cuda segmented cum prod inclusive", "[cuda][cum_prod]") {

  size_t n = 12;
  size_t stride = 3;
  float *h_vals = (float *)malloc(sizeof(float) * n);
  for (int i = 0; i < n; ++i) {
    h_vals[i] = i;
  }
  float *h_rets = (float *)malloc(sizeof(float) * n);

  cudalab::cudaSegCumProdByCub(h_vals, h_rets, stride, n, true);

  int s = 0;
  float p = 0.0;

  for (int i = 0; i < n; ++i) {

    s %= stride;

    if (s == 0) {
      p = 1.0;
    } else {
      p *= h_vals[i - 1];
    }
    REQUIRE_THAT(h_rets[i], Catch::Matchers::WithinAbs(p, 1E-6));

    s += 1;
  }
}

TEST_CASE("cuda cum prod benchmark", "[cuda][cum_prod][benchmark]") {

  size_t n = 10240000;

  float *h_vals = cudalab::common::randomFloat(n, 0, 5);

  float *h_rets = (float *)malloc(sizeof(float) * n);

  BENCHMARK(fmt::format("cum prod cpu n={}", n)) {
    return cudalab::cumprod(h_vals, h_rets, n);
  };

  BENCHMARK(fmt::format("cum prod gpu n={}", n)) {
    return cudalab::cudaCumProd3Phase(h_vals, h_rets, n);
  };

  BENCHMARK(fmt::format("cum prod gpu cub n={}", n)) {
    return cudalab::cudaCumProdByCub(h_vals, h_rets, n);
  };
}