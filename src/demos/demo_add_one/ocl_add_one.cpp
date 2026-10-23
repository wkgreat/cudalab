#include "ocl_add_one.h"

#include <CL/cl.h>
#include <CL/cl_platform.h>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

#define CHECK_ERR(err, msg)                                                    \
  if (err != CL_SUCCESS) {                                                     \
    fprintf(stderr, "Error %d at %s\n", err, msg);                             \
    return 1;                                                                  \
  }

namespace cudalab {

namespace ocl {

int oclAddOne(int *h_vals, int n) {

  cl_int err;
  cl_platform_id platform = NULL;
  cl_device_id device;
  cl_context ctx;
  cl_command_queue queue;
  cl_program prog;
  cl_kernel kernel;

  cl_uint num_platforms = 0;

  err = clGetPlatformIDs(0, NULL, &num_platforms);
  CHECK_ERR(err, "get platform count");
  if (num_platforms == 0) {
    fprintf(stderr, "Error: no OpenCL platform found\n");
    return 1;
  }

  cl_platform_id *platforms =
      (cl_platform_id *)malloc(sizeof(cl_platform_id) * num_platforms);

  err = clGetPlatformIDs(num_platforms, platforms, NULL);
  if (err != CL_SUCCESS) {
    free(platforms);
    fprintf(stderr, "Error %d at %s\n", err, "get platforms");
    return 1;
  }

  cl_platform_id nvidia = NULL;
  char platformName[128] = {};
  for (cl_uint i = 0; i < num_platforms; ++i) {
    err = clGetPlatformInfo(platforms[i], CL_PLATFORM_NAME,
                            sizeof(platformName) - 1, platformName, NULL);
    CHECK_ERR(err, "get platform info");
    printf("platform[%u] = %s\n", i, platformName);

    if (strstr(platformName, "NVIDIA") != NULL) {
      nvidia = platforms[i];
    }
  }

  platform = nvidia != NULL ? nvidia : platforms[0];
  free(platforms);

  err = clGetDeviceIDs(platform, CL_DEVICE_TYPE_GPU, 1, &device, NULL);

  if (err != CL_SUCCESS) {
    err = clGetDeviceIDs(platform, CL_DEVICE_TYPE_CPU, 1, &device, NULL);
  }

  CHECK_ERR(err, "get device");

  ctx = clCreateContext(NULL, 1, &device, NULL, NULL, &err);
  CHECK_ERR(err, "create context");

  queue = clCreateCommandQueueWithProperties(ctx, device, NULL, &err);
  CHECK_ERR(err, "create queue");

  std::ifstream file("ocl_add_one.cl");
  if (!file.is_open()) {
    std::cerr << "cannot open cl file" << std::endl;
    return 1;
  }
  std::stringstream srcbuf;
  srcbuf << file.rdbuf();
  std::string srcstr = srcbuf.str();
  size_t src_len = srcstr.length();
  const char *src = srcstr.c_str();

  prog = clCreateProgramWithSource(ctx, 1, &src, &src_len, &err);
  CHECK_ERR(err, "create prog");

  err = clBuildProgram(prog, 1, &device, "", NULL, NULL);
  CHECK_ERR(err, "build program");

  kernel = clCreateKernel(prog, "add_one", &err);
  CHECK_ERR(err, "create kernel");

  cl_mem d_vals = clCreateBuffer(ctx, CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR,
                                 n * sizeof(int), h_vals, &err);
  CHECK_ERR(err, "create d_vals");

  err = clSetKernelArg(kernel, 0, sizeof(cl_mem), &d_vals);
  CHECK_ERR(err, "set kernel arg d_vals");

  err = clSetKernelArg(kernel, 1, sizeof(int), &n);
  CHECK_ERR(err, "set kernel arg N");

  size_t local_size = 256;
  size_t global_size = (n + local_size - 1) / local_size * local_size;

  err = clEnqueueNDRangeKernel(queue, kernel, 1, NULL, &global_size,
                               &local_size, 0, NULL, NULL);
  CHECK_ERR(err, "equeue kernel");

  err = clEnqueueReadBuffer(queue, d_vals, CL_TRUE, 0, sizeof(int) * n, h_vals,
                            0, NULL, NULL);
  CHECK_ERR(err, "equeue read buffer");

  clReleaseKernel(kernel);
  clReleaseProgram(prog);
  clReleaseMemObject(d_vals);
  clReleaseCommandQueue(queue);
  clReleaseContext(ctx);

  return 0;
}

} // namespace ocl
} // namespace cudalab