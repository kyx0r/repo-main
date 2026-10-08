#include <hip/hip_runtime.h>
#include <hip/hiprtc.h>
#include <cstdio>
#include <string>
#include <vector>

#define HIP(call) do { const hipError_t err = (call); if (err != hipSuccess) { \
    std::fprintf(stderr, "%s: %s\n", #call, hipGetErrorString(err)); return 1; } } while (0)
#define RTC(call) do { const hiprtcResult err = (call); if (err != HIPRTC_SUCCESS) { \
    std::fprintf(stderr, "%s: %s\n", #call, hiprtcGetErrorString(err)); return 1; } } while (0)

int main() {
    hipDeviceProp_t prop{};
    HIP(hipGetDeviceProperties(&prop, 0));
    const std::string arch = std::string("--gpu-architecture=") + prop.gcnArchName;
    const char *options[] = {arch.c_str()};
    const char *source = R"(
        extern "C" __global__ void add_two(float *values) {
            const unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
            if (i < 1024) values[i] += 2.0f;
        }
    )";
    hiprtcProgram program{};
    RTC(hiprtcCreateProgram(&program, source, "add_two.hip", 0, nullptr, nullptr));
    const hiprtcResult result = hiprtcCompileProgram(program, 1, options);
    if (result != HIPRTC_SUCCESS) {
        size_t length = 0;
        RTC(hiprtcGetProgramLogSize(program, &length));
        std::vector<char> log(length + 1, 0);
        RTC(hiprtcGetProgramLog(program, log.data()));
        std::fprintf(stderr, "%s\n%s\n", hiprtcGetErrorString(result), log.data());
        return 1;
    }
    size_t length = 0;
    RTC(hiprtcGetCodeSize(program, &length));
    std::vector<char> code(length);
    RTC(hiprtcGetCode(program, code.data()));
    RTC(hiprtcDestroyProgram(&program));
    hipModule_t module{};
    hipFunction_t kernel{};
    HIP(hipModuleLoadData(&module, code.data()));
    HIP(hipModuleGetFunction(&kernel, module, "add_two"));
    float host[1024]{};
    float *device = nullptr;
    HIP(hipMalloc(&device, sizeof(host)));
    HIP(hipMemcpy(device, host, sizeof(host), hipMemcpyHostToDevice));
    void *arguments[] = {&device};
    HIP(hipModuleLaunchKernel(kernel, 4, 1, 1, 256, 1, 1, 0, nullptr, arguments, nullptr));
    HIP(hipDeviceSynchronize());
    HIP(hipMemcpy(host, device, sizeof(host), hipMemcpyDeviceToHost));
    HIP(hipFree(device));
    HIP(hipModuleUnload(module));
    for (float value : host) if (value != 2.0f) {
        std::fprintf(stderr, "HIPRTC kernel result mismatch\n"); return 1;
    }
    std::printf("HIPRTC/COMGR JIT kernel PASS (%s)\n", prop.gcnArchName);
}
