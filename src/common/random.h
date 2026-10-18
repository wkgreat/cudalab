#pragma once

#include <cstddef>
namespace cudalab {
namespace common {

int *randomInt(size_t n);

int *randomInt(size_t n, int minValue, int maxValue);

float *randomFloat(size_t n);

float *randomFloat(size_t n, float minValue, int maxValue);

void seedRandom(unsigned int seed);

} // namespace common
} // namespace cudalab
