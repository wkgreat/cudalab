// main.cpp - host driver for the add_one CUDA sample.
//
// Plain C++ compiled by MSVC. It allocates the device buffer, calls the
// add_one() launcher declared in add_one.h, then verifies the result against a
// reference computed on the CPU.

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include <cuda_runtime.h>

#include "add_one.h"

namespace {

// Abort with a readable message on an unrecoverable CUDA runtime error.
void check(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        std::fprintf(stderr, "error: %s failed: %s\n", what, cudaGetErrorString(err));
        std::exit(EXIT_FAILURE);
    }
}

}  // namespace

int main() {
    constexpr std::size_t kN = 1u << 20;  // 1,048,576 floats = 4 MiB
    constexpr float kIncrement = 1.0f;

    // --- Describe the device that will run the kernel -----------------------
    int device = 0;
    check(cudaGetDevice(&device), "cudaGetDevice");

    cudaDeviceProp prop{};
    check(cudaGetDeviceProperties(&prop, device), "cudaGetDeviceProperties");

    std::printf("device %d            : %s\n", device, prop.name);
    std::printf("compute capability   : sm_%d%d\n", prop.major, prop.minor);
    std::printf("multiprocessors      : %d\n", prop.multiProcessorCount);
    std::printf("elements             : %zu\n", kN);

    // --- Prepare host and device data ---------------------------------------
    std::vector<float> host(kN);
    for (std::size_t i = 0; i < kN; ++i) {
        host[i] = static_cast<float>(i) * 0.5f;
    }

    float* device_data = nullptr;
    check(cudaMalloc(&device_data, kN * sizeof(float)), "cudaMalloc");
    check(cudaMemcpy(device_data, host.data(), kN * sizeof(float), cudaMemcpyHostToDevice),
          "cudaMemcpy(host -> device)");

    // --- Run the kernel, timed so the launch is known to be asynchronous ----
    const auto start = std::chrono::steady_clock::now();

    check(cudalab::add_one(device_data, kN), "cudalab::add_one");
    check(cudaDeviceSynchronize(), "cudaDeviceSynchronize");

    const auto stop = std::chrono::steady_clock::now();
    const double ms = std::chrono::duration<double, std::milli>(stop - start).count();

    std::printf("block size           : %d threads\n", cudalab::add_one_block_size());
    std::printf("kernel time          : %.3f ms (%.1f GB/s effective)\n", ms,
                (2.0 * static_cast<double>(kN) * sizeof(float)) / (ms * 1e-3) / 1e9);

    // --- Copy back and verify against the CPU reference ---------------------
    check(cudaMemcpy(host.data(), device_data, kN * sizeof(float), cudaMemcpyDeviceToHost),
          "cudaMemcpy(device -> host)");
    check(cudaFree(device_data), "cudaFree");

    std::size_t mismatches = 0;
    float max_abs_err = 0.0f;
    for (std::size_t i = 0; i < kN; ++i) {
        const float expected = static_cast<float>(i) * 0.5f + kIncrement;
        const float err = host[i] - expected;
        const float abs_err = err < 0.0f ? -err : err;
        if (abs_err > max_abs_err) {
            max_abs_err = abs_err;
        }
        if (host[i] != expected) {
            if (mismatches < 5) {
                std::fprintf(stderr, "mismatch at %zu: got %g, expected %g\n", i,
                             static_cast<double>(host[i]), static_cast<double>(expected));
            }
            ++mismatches;
        }
    }

    std::printf("max abs error        : %g\n", static_cast<double>(max_abs_err));

    if (mismatches != 0) {
        std::fprintf(stderr, "FAIL: %zu of %zu elements are wrong\n", mismatches, kN);
        return EXIT_FAILURE;
    }

    std::printf("PASS: all %zu elements incremented by %g on the GPU\n", kN,
                static_cast<double>(kIncrement));
    return EXIT_SUCCESS;
}
