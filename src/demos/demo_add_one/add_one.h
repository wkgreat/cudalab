// add_one.h - host-callable interface to the add_one CUDA kernel.
//
// This header is plain C++: the host driver (main.cpp, same directory) includes
// it and is compiled by MSVC, while the implementation (add_one.cu, same
// directory) is compiled by nvcc. Everything CUDA-specific stays inside the .cu
// translation unit, and the demo directory is on its own include path.

#pragma once

#include <cstddef>

#include <cuda_runtime.h>

namespace cudalab {

// Adds 1.0f to every element of the device buffer `data`, which must hold at
// least `n` floats.
//
// The launch is asynchronous: it returns as soon as the kernel has been
// enqueued on `stream` (nullptr means the default stream). Call
// cudaDeviceSynchronize() or cudaStreamSynchronize(stream) before reading the
// result.
//
// Returns cudaSuccess if the kernel was launched, or the error reported by
// cudaGetLastError() otherwise. Launch failures are not sticky: the error is
// returned to the caller rather than being left in the runtime's last-error
// slot.
[[nodiscard]] cudaError_t add_one(float* data, std::size_t n, cudaStream_t stream = nullptr) noexcept;

// Number of threads per block used by add_one(); exposed so the driver can
// print (and optionally check) the launch configuration.
int add_one_block_size() noexcept;

}  // namespace cudalab
