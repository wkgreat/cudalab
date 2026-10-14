// Catch2 tests for the bitonic sort demo.
//
// Correctness: both implementations - the CPU one and the CUDA one - are
// compared element by element against std::sort. The sweep covers ascending
// and descending order, sizes that are powers of two (bitonic sort needs no
// padding) and sizes that are not (both implementations must pad with a
// sentinel and then drop it again), and several input shapes including ones
// built from INT_MIN / INT_MAX, the sentinel values themselves.
//
// Performance: the case at the bottom uses Catch2's BENCHMARK and is tagged
// [benchmark]. It runs together with the rest of the suite, CTest only trims it
// to a small sample count so the timing table stays cheap. To run just it, with
// the full sample count, and in a Release build where the numbers mean
// something:
//
//   ./build/ninja-release/demo_bitonic_sort_test "[benchmark]"
//   ./build/ninja-release/demo_bitonic_sort_test "[benchmark]" --benchmark-samples 100
//
// The demo's driver (main.cpp) is deliberately not part of this target: this
// file has no main(), Catch2::Catch2WithMain provides one.

#include <catch2/benchmark/catch_benchmark.hpp>
#include <catch2/catch_test_macros.hpp>
#include <catch2/generators/catch_generators.hpp>

// Registers the `oneline` reporter (one line per test case, benchmark means
// appended). Opt in on the command line with `--reporter oneline`; ctest and
// plain runs keep Catch2's stock `console` reporter.
#include "cudalab/oneline_reporter.hpp"

#include <algorithm>
#include <climits>
#include <cstddef>
#include <functional>
#include <random>
#include <string>
#include <vector>

#include "bitonic_sort.h"

namespace {

using SortFn = int (*)(int *, int *, std::size_t, bool);

// cudaBitonicSortInt returns cudaError_t; wrap it so both implementations have
// the same shape and a single checker can drive them.
int cudaSortInt(int *vals, int *out, std::size_t n, bool asc) {
  return static_cast<int>(cudalab::cudaBitonicSortInt(vals, out, n, asc));
}

// Sizes worth sweeping. 0/1 are the empty and singleton edge cases, 2/8/16/32/
// 1024 are powers of two and 3/7/15/17/31/33/1000/1025 are not, so every
// padding path is exercised.
std::size_t sweepSize() {
  return GENERATE(std::size_t{0}, std::size_t{1}, std::size_t{2},
                  std::size_t{3}, std::size_t{7}, std::size_t{8},
                  std::size_t{15}, std::size_t{16}, std::size_t{17},
                  std::size_t{31}, std::size_t{32}, std::size_t{33},
                  std::size_t{1000}, std::size_t{1024}, std::size_t{1025});
}

enum class Shape { Random, Sorted, Reversed, Duplicates, Extreme };

const char *shapeName(Shape shape) {
  switch (shape) {
  case Shape::Random:
    return "random";
  case Shape::Sorted:
    return "sorted";
  case Shape::Reversed:
    return "reversed";
  case Shape::Duplicates:
    return "duplicates";
  case Shape::Extreme:
    return "extreme";
  }
  return "?";
}

std::vector<int> makeInput(Shape shape, std::size_t n) {
  std::vector<int> values(n);
  switch (shape) {
  case Shape::Random: {
    std::mt19937 engine{20261014u};
    std::uniform_int_distribution<int> dist(INT_MIN, INT_MAX);
    for (int &v : values) {
      v = dist(engine);
    }
    break;
  }
  case Shape::Sorted:
    for (std::size_t i = 0; i < n; ++i) {
      values[i] = static_cast<int>(i);
    }
    break;
  case Shape::Reversed:
    for (std::size_t i = 0; i < n; ++i) {
      values[i] = static_cast<int>(n - i);
    }
    break;
  case Shape::Duplicates: {
    std::mt19937 engine{7u};
    std::uniform_int_distribution<int> dist(-3, 3);
    for (int &v : values) {
      v = dist(engine);
    }
    break;
  }
  case Shape::Extreme:
    // Both padding sentinels also appear as real data, so a lost or misplaced
    // one shows up as a mismatch rather than hiding in the padding.
    for (std::size_t i = 0; i < n; ++i) {
      values[i] = (i % 2 == 0) ? INT_MAX : INT_MIN;
    }
    break;
  }
  return values;
}

std::vector<int> sortedReference(const std::vector<int> &input, bool asc) {
  std::vector<int> expected = input;
  if (asc) {
    std::sort(expected.begin(), expected.end());
  } else {
    std::sort(expected.begin(), expected.end(), std::greater<int>());
  }
  return expected;
}

// Compares two arrays and reports only the first mismatch, with a handful of
// neighbours for context. A plain `REQUIRE(actual == expected)` would print both
// vectors in full - over a million ints in the large cases - burying the single
// value that is actually wrong.
void requireSameValues(const std::vector<int> &actual,
                       const std::vector<int> &expected) {
  REQUIRE(actual.size() == expected.size());

  for (std::size_t i = 0; i < expected.size(); ++i) {
    if (actual[i] != expected[i]) {
      FAIL("first of " << (actual.size() - i)
                       << " mismatches at index " << i << ": expected "
                       << expected[i] << ", got " << actual[i]
                       << " (size " << expected.size() << ")");
    }
  }
}

// Runs `sort` over one generated input and compares the result with std::sort.
void requireMatchesReference(SortFn sort, std::size_t n, bool asc, Shape shape) {
  std::vector<int> input = makeInput(shape, n);
  const std::vector<int> expected = sortedReference(input, asc);

  std::vector<int> output(n, 0);
  const int rc = sort(input.data(), output.data(), n, asc);

  REQUIRE(rc == 0);
  requireSameValues(output, expected);
}

} // namespace

TEST_CASE("bitonicSortInt sorts like std::sort", "[bitonic][cpu]") {
  const std::size_t n = sweepSize();
  const bool asc = GENERATE(true, false);
  const Shape shape = GENERATE(Shape::Random, Shape::Sorted, Shape::Reversed,
                               Shape::Duplicates, Shape::Extreme);

  DYNAMIC_SECTION("n=" << n << ", asc=" << asc << ", " << shapeName(shape)) {
    requireMatchesReference(cudalab::bitonicSortInt, n, asc, shape);
  }
}

TEST_CASE("cudaBitonicSortInt sorts like std::sort", "[bitonic][cuda]") {
  const std::size_t n = sweepSize();
  const bool asc = GENERATE(true, false);
  const Shape shape = GENERATE(Shape::Random, Shape::Sorted, Shape::Reversed,
                               Shape::Duplicates, Shape::Extreme);

  DYNAMIC_SECTION("n=" << n << ", asc=" << asc << ", " << shapeName(shape)) {
    requireMatchesReference(cudaSortInt, n, asc, shape);
  }
}

TEST_CASE("both implementations sort a size that is not a power of two",
          "[bitonic]") {
  // 1,024,000 is what main.cpp sorts: 1,048,576 is the next power of two, so
  // both implementations have to pad ~24k elements and hide them again.
  constexpr std::size_t kN = 1024000;

  const bool asc = GENERATE(true, false);
  DYNAMIC_SECTION("bitonicSortInt asc=" << asc) {
    requireMatchesReference(cudalab::bitonicSortInt, kN, asc, Shape::Random);
  }
  DYNAMIC_SECTION("cudaBitonicSortInt asc=" << asc) {
    requireMatchesReference(cudaSortInt, kN, asc, Shape::Random);
  }
}

TEST_CASE("sorting a buffer in place matches sorting into a separate one",
          "[bitonic]") {
  // main.cpp calls both implementations with h_vals == h_out; make sure that
  // aliasing is fine, not just the documented two-buffer form. The generated
  // size is not a multiple of the block size, so the tail is covered too.
  constexpr std::size_t kN = 4099;

  const auto sort = GENERATE(cudalab::bitonicSortInt, cudaSortInt);

  std::vector<int> input = makeInput(Shape::Random, kN);
  const std::vector<int> expected = sortedReference(input, true);

  REQUIRE(sort(input.data(), input.data(), kN, true) == 0);
  requireSameValues(input, expected);
}

TEST_CASE("the sorted result stays sorted in the requested order", "[bitonic]") {
  // A cheap invariant check on top of the exact comparison above: catches an
  // implementation that returns the wrong order overall.
  constexpr std::size_t kN = 1025;

  const auto sort = GENERATE(cudalab::bitonicSortInt, cudaSortInt);
  const bool asc = GENERATE(true, false);

  std::vector<int> input = makeInput(Shape::Random, kN);
  std::vector<int> output(kN, 0);
  REQUIRE(sort(input.data(), output.data(), kN, asc) == 0);

  for (std::size_t i = 1; i < kN; ++i) {
    if (asc) {
      REQUIRE(output[i - 1] <= output[i]);
    } else {
      REQUIRE(output[i - 1] >= output[i]);
    }
  }
}

TEST_CASE("bitonic sort performance", "[bitonic][benchmark]") {
  // Both implementations sort the *same* size, so the two rows of Catch2's
  // table are directly comparable instead of measuring two different problems.
  // 2^18 is large enough for the GPU work to outweigh launch overhead, yet
  // small enough that a Debug build still finishes quickly under ctest. For
  // numbers that mean something, run a Release build (and let Catch2 use its
  // default 100 samples).
  constexpr std::size_t kN = std::size_t{1} << 18; // 262,144

  const std::vector<int> input = makeInput(Shape::Random, kN);
  std::vector<int> cpuOutput(kN, 0);
  std::vector<int> cudaOutput(kN, 0);

  BENCHMARK("bitonicSortInt (CPU, n=" + std::to_string(kN) + ")") {
    return cudalab::bitonicSortInt(const_cast<int *>(input.data()),
                                   cpuOutput.data(), kN, true);
  };

  BENCHMARK("cudaBitonicSortInt (GPU, n=" + std::to_string(kN) + ")") {
    return static_cast<int>(cudalab::cudaBitonicSortInt(
        const_cast<int *>(input.data()), cudaOutput.data(), kN, true));
  };
}
