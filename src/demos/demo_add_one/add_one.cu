// add_one.cu - the CUDA side of the add_one sample.
//
// Compiled by nvcc. Contains the __global__ kernel and a plain host function
// that launches it, so that host code in other translation units can call it
// without knowing any CUDA launch syntax.

#include "add_one.h"

#include <algorithm>

namespace cudalab {
namespace {

constexpr int kBlockSize = 256;

// Upper bound on the grid size. 2^31 - 1 blocks is the hardware limit on x,
// but a modest cap keeps the grid-stride loop in charge and avoids asking for
// an absurd number of blocks for very large inputs.
constexpr std::size_t kMaxBlocks = 1u << 20;

// Each thread adds 1.0f to the elements it owns, striding through the buffer
// so that any n (including n smaller than the grid, or far larger) is handled
// by one launch configuration.
__global__ void add_one_kernel(float* __restrict__ data, std::size_t n) {
    const std::size_t stride = static_cast<std::size_t>(blockDim.x) * gridDim.x;
    for (std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x; i < n; i += stride) {
        data[i] += 1.0f;
    }
}

}  // namespace

int add_one_block_size() noexcept { return kBlockSize; }

cudaError_t add_one(float* data, std::size_t n, cudaStream_t stream) noexcept {
    if (n == 0) {
        return cudaSuccess;  // nothing to do; stays a no-op instead of a launch
    }

    const std::size_t blocks_needed = (n + kBlockSize - 1) / kBlockSize;
    const int blocks = static_cast<int>(std::min(blocks_needed, kMaxBlocks));

    add_one_kernel<<<blocks, kBlockSize, 0, stream>>>(data, n);

    // Report any launch-time error (bad configuration, invalid argument, ...)
    // to the caller instead of leaving it in the runtime's last-error slot.
    return cudaGetLastError();
}

}  // namespace cudalab
