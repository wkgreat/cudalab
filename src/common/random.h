#pragma once

#include <cstddef>
namespace cudalab {
namespace common {

// Allocates an array of n random ints and returns it. The caller owns the result
// and releases it with delete[].
//
// Values cover the whole int range. The generator starts from a fixed seed so a
// run stays reproducible, but it keeps advancing, so successive calls return
// different values. n == 0 is valid and yields a non-null, deletable array.
int *randomInt(size_t n);

// Same, with every value drawn uniformly from [minValue, maxValue], both ends
// included. Throws std::invalid_argument when minValue > maxValue.
int *randomInt(size_t n, int minValue, int maxValue);

// Reseeds the calling thread's generator, which makes the following sequence
// reproducible. Pass std::random_device{}() for a fresh sequence on every run.
void seedRandom(unsigned int seed);

}
} // namespace cudalab
