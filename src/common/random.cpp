#include "common/random.h"

#include <cstdlib>
#include <limits>
#include <random>
#include <stdexcept>

namespace cudalab {
namespace common {
namespace {

// A fixed default seed keeps a failing case reproducible; seedRandom() exists
// to change it on purpose. The engine is thread_local so concurrent callers
// cannot race on its state - each thread simply gets its own sequence.
constexpr unsigned int kDefaultSeed = 20261008u;

std::mt19937 &generator() {
  thread_local std::mt19937 engine{kDefaultSeed};
  return engine;
}

} // namespace

void seedRandom(unsigned int seed) { generator().seed(seed); }

int *randomInt(size_t n) {
  return randomInt(n, std::numeric_limits<int>::min(),
                   std::numeric_limits<int>::max());
}

int *randomInt(size_t n, int minValue, int maxValue) {
  if (minValue > maxValue) {
    throw std::invalid_argument(
        "randomInt: minValue must not be greater than maxValue");
  }

  // new int[0] is a valid, non-null, deletable allocation, so a caller never
  // has to special-case an empty request.
  int *values = (int *)std::malloc(sizeof(int) * n);

  std::uniform_int_distribution<int> distribution(minValue, maxValue);
  std::mt19937 &engine = generator();
  for (size_t i = 0; i < n; ++i) {
    values[i] = distribution(engine);
  }

  return values;
}

float *randomFloat(size_t n) { return randomFloat(n, 0.0f, 1.0f); }

float *randomFloat(size_t n, float minValue, int maxValue) {
  if (minValue > static_cast<float>(maxValue)) {
    throw std::invalid_argument(
        "randomFloat: minValue must not be greater than maxValue");
  }

  // Same allocation convention as randomInt: the caller owns the block.
  float *values = (float *)std::malloc(sizeof(float) * n);

  // uniform_real_distribution is half-open: minValue is reachable, maxValue is
  // not. That is the opposite of uniform_int_distribution above, where both
  // endpoints are inclusive.
  std::uniform_real_distribution<float> distribution(
      minValue, static_cast<float>(maxValue));
  std::mt19937 &engine = generator();
  for (size_t i = 0; i < n; ++i) {
    values[i] = distribution(engine);
  }

  return values;
}

} // namespace common
} // namespace cudalab
