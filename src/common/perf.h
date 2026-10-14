#pragma once

#include <chrono>
namespace cudalab {

namespace perf {

class Clock {

public:
  using time_point =
      std::chrono::time_point<std::chrono::high_resolution_clock>;

  Clock() = default;

  time_point starttime;
  time_point stoptime;

  void start();
  void stop();
  std::chrono::nanoseconds duration();
};

} // namespace perf

} // namespace cudalab