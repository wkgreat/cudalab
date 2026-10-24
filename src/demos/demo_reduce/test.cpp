#include <catch2/benchmark/catch_benchmark.hpp>
#include <catch2/catch_test_macros.hpp>
#include <catch2/generators/catch_generators.hpp>
#include <catch2/matchers/catch_matchers.hpp>
#include <catch2/matchers/catch_matchers_floating_point.hpp>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <fmt/format.h>

#include "common/random.h"
#include "reduce.h"

TEST_CASE("cuda reduce sum int", "[cuda][reduce][sum]") {

  constexpr int n = 4;
  int h_vals[n] = {1, 2, 3, 4};
  int h_out;
  int err = cudalab::cudaSumByCub(h_vals, n, &h_out);
  REQUIRE(err == 0);
  int s = 0;
  for (int i = 0; i < n; ++i) {
    s += h_vals[i];
  }
  REQUIRE(h_out == s);
}
TEST_CASE("cuda reduce sum int4", "[cuda][reduce][sum]") {

  constexpr int n = 4;
  cudalab::Int4 h_vals[n] = {
      {1, 2, 3, 4}, {5, 6, 7, 8}, {9, 10, 11, 12}, {13, 14, 15, 16}};
  cudalab::Int4 h_out;
  int err = cudalab::cudaSumByCub(h_vals, n, &h_out);
  REQUIRE(err == 0);
  cudalab::Int4 s{0, 0, 0, 0};
  for (int i = 0; i < n; ++i) {
    s.x += h_vals[i].x;
    s.y += h_vals[i].y;
    s.z += h_vals[i].z;
    s.w += h_vals[i].w;
  }
  REQUIRE(s.x == h_out.x);
  REQUIRE(s.y == h_out.y);
  REQUIRE(s.z == h_out.z);
  REQUIRE(s.w == h_out.w);
}

cudalab::Int4 Int4Add(cudalab::Int4 a, cudalab::Int4 b) {
  return {a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w};
}

bool Int4Eq(cudalab::Int4 a, cudalab::Int4 b) {
  return a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;
}

TEST_CASE("cuda sgement reduce sum int", "[cuda][reduce][segment][sum]") {

  constexpr int n = 6;
  constexpr int stride = 2;
  size_t nsegs;
  cudalab::Int4 h_vals[n] = {{1, 2, 3, 4},     {5, 6, 7, 8},
                             {9, 10, 11, 12},  {13, 14, 15, 16},
                             {17, 18, 19, 20}, {21, 22, 23, 24}};
  cudalab::Int4 h_out[3];
  int err = cudalab::cudaSegSumByCub(h_vals, stride, n, h_out, &nsegs);
  REQUIRE(err == 0);
  REQUIRE(nsegs == 3);
  cudalab::Int4 h_sum[3];
  h_sum[0] = Int4Add(h_vals[0], h_vals[1]);
  h_sum[1] = Int4Add(h_vals[2], h_vals[3]);
  h_sum[2] = Int4Add(h_vals[4], h_vals[5]);

  REQUIRE(Int4Eq(h_out[0], h_sum[0]));
  REQUIRE(Int4Eq(h_out[1], h_sum[1]));
  REQUIRE(Int4Eq(h_out[2], h_sum[2]));
}
