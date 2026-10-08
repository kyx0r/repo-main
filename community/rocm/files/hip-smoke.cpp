#include <hip/hip_runtime.h>
#include <cstdio>

#define HIP(call) do { const hipError_t err = (call); if (err != hipSuccess) { \
    std::fprintf(stderr, "%s: %s\n", #call, hipGetErrorString(err)); return 1; } } while (0)

__global__ void add_one(float *values) {
    const unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < 1024) values[i] += 1.0f;
}

int main() {
    hipDeviceProp_t prop{};
    HIP(hipGetDeviceProperties(&prop, 0));
    std::printf("HIP device: %s (%s)\n", prop.name, prop.gcnArchName);
    float host[1024]{};
    float *device = nullptr;
    HIP(hipMalloc(&device, sizeof(host)));
    HIP(hipMemcpy(device, host, sizeof(host), hipMemcpyHostToDevice));
    hipLaunchKernelGGL(add_one, dim3(4), dim3(256), 0, 0, device);
    HIP(hipGetLastError());
    HIP(hipDeviceSynchronize());
    HIP(hipMemcpy(host, device, sizeof(host), hipMemcpyDeviceToHost));
    HIP(hipFree(device));
    for (float value : host) if (value != 1.0f) {
        std::fprintf(stderr, "HIP kernel result mismatch\n"); return 1;
    }
    std::puts("HIP kernel PASS");
}
