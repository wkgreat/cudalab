// A Catch2 reporter that prints one line per test case, with the benchmark
// information kept out of that line:
//
//     both implementations sort a size that is not a power of two PASS
//     bitonic sort performance ........................... PASS
//         bitonicSortInt (CPU, n=262144)                      96.191 ms
//         cudaBitonicSortInt (GPU, n=262144)                   1.779 ms
//
// Any BENCHMARK that ran inside a test case gets its mean on an indented line
// below the verdict, so the case line stays scannable while the numbers are
// still there. After the whole run, the complete benchmark table - samples,
// iterations, estimated run time, mean/low/high and std dev/low/high - is
// printed once under a "benchmark results" heading.
//
// Assertion failures still print under their case line, so a failing run is as
// informative as the console reporter.
//
// Select it with `--reporter oneline`; `--reporter console` keeps the stock
// report. The reporter is registered by including this header, so include it
// from *one* translation unit per test executable.
//
// CATCH_REGISTER_REPORTER already wraps its static in an anonymous namespace, so
// including this header in several TUs of the same binary is harmless apart from
// registering the same name more than once - which is why we say "one TU".

#ifndef CUDALAB_ONELINE_REPORTER_HPP
#define CUDALAB_ONELINE_REPORTER_HPP

#include <catch2/benchmark/detail/catch_benchmark_stats.hpp>
#include <catch2/catch_assertion_result.hpp>
#include <catch2/catch_test_case_info.hpp>
#include <catch2/interfaces/catch_interfaces_reporter.hpp>
#include <catch2/reporters/catch_reporter_registrars.hpp>
#include <catch2/reporters/catch_reporter_streaming_base.hpp>

#include <algorithm>
#include <cstddef>
#include <iomanip>
#include <ostream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace cudalab::testing {

class OneLineReporter : public Catch::StreamingReporterBase {
public:
  explicit OneLineReporter(Catch::ReporterConfig &&config)
      : Catch::StreamingReporterBase(std::move(config)) {}

  static std::string getDescription() {
    return "One line per test case, benchmarks indented, full table at the end";
  }

  void testCaseStarting(Catch::TestCaseInfo const &info) override {
    Catch::StreamingReporterBase::testCaseStarting(info);
    m_caseBenchmarks.clear();
  }

  void benchmarkEnded(Catch::BenchmarkStats<> const &stats) override {
    m_caseBenchmarks.push_back(stats);
    m_allBenchmarks.push_back(stats);
  }

  // Only failures get extra lines; the default console reporter prints every
  // assertion, which is exactly the noise this reporter exists to remove.
  void assertionEnded(Catch::AssertionStats const &stats) override {
    const Catch::AssertionResult &result = stats.assertionResult;
    if (result.isOk()) {
      return;
    }

    const Catch::SourceLineInfo loc = result.getSourceInfo();
    m_stream << "      " << loc.file << ':' << loc.line << "  "
             << result.getExpression() << '\n';

    if (result.hasExpandedExpression()) {
      const std::string expanded = result.getExpandedExpression();
      if (expanded != result.getExpression()) {
        m_stream << "        " << expanded << '\n';
      }
    }
    if (result.hasMessage()) {
      m_stream << "        " << std::string(result.getMessage()) << '\n';
    }
  }

  void testCaseEnded(Catch::TestCaseStats const &stats) override {
    const std::string name = stats.testInfo->name;
    const bool ok = stats.totals.assertions.allOk();

    // Name, dot leader, verdict - the shape of ctest's own per-test line.
    constexpr std::size_t kNameWidth = 60;
    m_stream << name;
    if (name.size() < kNameWidth) {
      m_stream << ' ' << std::string(kNameWidth - name.size() - 1, '.');
    } else {
      m_stream << ' ';
    }
    m_stream << (ok ? "PASS" : "FAIL") << '\n';

    // Benchmarks go on their own indented lines, names aligned within the case.
    if (!m_caseBenchmarks.empty()) {
      std::size_t width = 0;
      for (const Catch::BenchmarkStats<> &bench : m_caseBenchmarks) {
        width = std::max(width, bench.info.name.size());
      }
      for (const Catch::BenchmarkStats<> &bench : m_caseBenchmarks) {
        m_stream << "    " << std::left << std::setw(static_cast<int>(width))
                 << bench.info.name << std::right << "  "
                 << formatDuration(bench.mean.point.count()) << '\n';
      }
    }

    Catch::StreamingReporterBase::testCaseEnded(stats);
  }

  void testRunEnded(Catch::TestRunStats const &stats) override {
    printBenchmarkTable();
    Catch::StreamingReporterBase::testRunEnded(stats);
  }

private:
  // A duration in nanoseconds, rendered in whichever unit keeps it readable.
  static std::string formatDuration(double nanoseconds) {
    std::ostringstream out;
    if (nanoseconds >= 1e9) {
      out << std::fixed << std::setprecision(3) << nanoseconds / 1e9 << " s";
    } else if (nanoseconds >= 1e6) {
      out << std::fixed << std::setprecision(3) << nanoseconds / 1e6 << " ms";
    } else if (nanoseconds >= 1e3) {
      out << std::fixed << std::setprecision(1) << nanoseconds / 1e3 << " us";
    } else {
      out << std::fixed << std::setprecision(0) << nanoseconds << " ns";
    }
    return out.str();
  }

  // One row per benchmark with every stat Catch2 collects, printed once after
  // the whole run. Columns mirror Catch2's own timing table.
  void printBenchmarkTable() {
    if (m_allBenchmarks.empty()) {
      return;
    }

    constexpr int kNameWidth = 40;
    constexpr int kNumWidth = 13;
    const std::string rule(79, '-');

    m_stream << '\n' << rule << '\n' << "benchmark results\n" << rule << '\n';
    m_stream << std::left << std::setw(kNameWidth) << "benchmark name" << std::right
             << std::setw(8) << "samples" << std::setw(7) << "iters"
             << std::setw(kNumWidth) << "est run" << std::setw(kNumWidth) << "mean"
             << std::setw(kNumWidth) << "low mean" << std::setw(kNumWidth)
             << "high mean" << std::setw(kNumWidth) << "std dev"
             << std::setw(kNumWidth) << "low std dev" << std::setw(kNumWidth)
             << "high std dev" << '\n';

    for (const Catch::BenchmarkStats<> &bench : m_allBenchmarks) {
      const Catch::BenchmarkInfo &info = bench.info;
      m_stream << std::left << std::setw(kNameWidth) << info.name << std::right
               << std::setw(8) << info.samples << std::setw(7) << info.iterations
               << std::setw(kNumWidth)
               << formatDuration(info.estimatedDuration)
               << std::setw(kNumWidth) << formatDuration(bench.mean.point.count())
               << std::setw(kNumWidth)
               << formatDuration(bench.mean.lower_bound.count())
               << std::setw(kNumWidth)
               << formatDuration(bench.mean.upper_bound.count())
               << std::setw(kNumWidth)
               << formatDuration(bench.standardDeviation.point.count())
               << std::setw(kNumWidth)
               << formatDuration(bench.standardDeviation.lower_bound.count())
               << std::setw(kNumWidth)
               << formatDuration(bench.standardDeviation.upper_bound.count())
               << '\n';
    }
  }

  // Benchmarks of the test case being run, and of the whole run.
  std::vector<Catch::BenchmarkStats<>> m_caseBenchmarks;
  std::vector<Catch::BenchmarkStats<>> m_allBenchmarks;
};

} // namespace cudalab::testing

CATCH_REGISTER_REPORTER("oneline", cudalab::testing::OneLineReporter)

#endif // CUDALAB_ONELINE_REPORTER_HPP
