#include "perf.h"
#include <chrono>

namespace cudalab {

namespace perf {

void Clock::start() { starttime = std::chrono::high_resolution_clock::now(); }
void Clock::stop() { stoptime = std::chrono::high_resolution_clock::now(); }
std::chrono::nanoseconds Clock::duration() {

  auto d = stoptime - starttime;
  return std::chrono::duration_cast<std::chrono::nanoseconds>(d);
}

} // namespace perf

} // namespace cudalab