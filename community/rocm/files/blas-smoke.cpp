#include <hip/hip_runtime.h>
#include <hipblas/hipblas.h>
#include <cmath>
#include <cstdio>

#define HIP(call) do { const hipError_t err = (call); if (err != hipSuccess) { \
    std::fprintf(stderr, "%s: %s\n", #call, hipGetErrorString(err)); return 1; } } while (0)
#define BLAS(call) do { const hipblasStatus_t err = (call); if (err != HIPBLAS_STATUS_SUCCESS) { \
    std::fprintf(stderr, "%s: hipBLAS status %d\n", #call, int(err)); return 1; } } while (0)

int main() {
    // Column-major matrices: [1 3; 2 4] * [5 7; 6 8].
    const float a[] = {1, 2, 3, 4}, b[] = {5, 6, 7, 8};
    const float expected[] = {23, 34, 31, 46};
    float c[4]{}, *da = nullptr, *db = nullptr, *dc = nullptr;
    HIP(hipMalloc(&da, sizeof(a)));
    HIP(hipMalloc(&db, sizeof(b)));
    HIP(hipMalloc(&dc, sizeof(c)));
    HIP(hipMemcpy(da, a, sizeof(a), hipMemcpyHostToDevice));
    HIP(hipMemcpy(db, b, sizeof(b), hipMemcpyHostToDevice));
    HIP(hipMemset(dc, 0, sizeof(c)));
    hipblasHandle_t handle;
    BLAS(hipblasCreate(&handle));
    const float alpha = 1.0f, beta = 0.0f;
    BLAS(hipblasSgemm(handle, HIPBLAS_OP_N, HIPBLAS_OP_N, 2, 2, 2,
                     &alpha, da, 2, db, 2, &beta, dc, 2));
    HIP(hipDeviceSynchronize());
    HIP(hipMemcpy(c, dc, sizeof(c), hipMemcpyDeviceToHost));
    BLAS(hipblasDestroy(handle));
    HIP(hipFree(da)); HIP(hipFree(db)); HIP(hipFree(dc));
    for (int i = 0; i < 4; ++i) if (std::fabs(c[i] - expected[i]) > 0.001f) {
        std::fprintf(stderr, "GEMM mismatch at %d: %f != %f\n", i, c[i], expected[i]); return 1;
    }
    std::puts("hipBLAS / rocBLAS GEMM PASS");
}
