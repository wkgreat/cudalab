#pragma once

namespace cudalab {

int cudaCumProd3Phase(float *h_vals, float *h_rets, size_t N);

// algorithm of cub
int cudaCumProd1Phase(float *h_vals, float *h_rets, size_t N);

} // namespace cudalab