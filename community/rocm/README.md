# ROCm 7.2.4 and Strata on KISS/musl (x86_64)

These packages provide the HIP compute subset of ROCm: a private AMD LLVM,
AMDGPU device bitcode, COMGR, the KFD/HSA runtime, HIP/hipcc, rocBLAS with
Tensile-generated GEMM kernels, hipBLAS, and rocminfo. `rocm` is a convenience
meta-package. This is a source port, not AMD's glibc binary distribution; no
`gcompat`, replacement libc, or changes to the system LLVM are used.

## Build and install

Put this community directory first in KISS_PATH (retain your core/extra/xorg
repositories). The new Python packages supply Tensile's build-time dependencies and HIP's
profiling-header generator (not the optional profiler runtime).
ROCR's trap-header generation also requires Bash and `xxd` (supplied by Vim);
these are declared build-only dependencies of `rocm-runtime`.
The dependency graph handles the order; a manual order for the compute stack is:

1. numactl, rocm-cmake, rocm-core, rocm-llvm
2. rocm-device-libs, rocm-comgr, rocm-hipcc, rocm-runtime
3. rocm-hip, rocminfo, hipblas-common
4. rocblas, hipblas, rocm, strata

```sh
export KISS_PATH="$PWD:$KISS_PATH"
export MAKEFLAGS=-j16
export CMAKE_BUILD_PARALLEL_LEVEL=16
export KISS_ROCM_ARCHS=gfx1100
kiss b rocm
kiss i rocm
kiss b strata
kiss i strata
```

KISS will build/install missing dependencies; review its prompts. LLVM and
rocBLAS are large builds: allow tens of GB of disk and several GB of RAM per
parallel compiler process. Put KISS_TMPDIR on disk, not a small tmpfs.
`KISS_ROCM_LINK_JOBS` (default 2) limits LLVM links and
`KISS_ROCM_TENSILE_JOBS` (default 8) limits kernel generation. Ninja is supplied
by the `samurai` package.

The ROCm prefix is `/usr/lib/rocm`, and LLVM lives in `/usr/lib/rocm/llvm`.
Libraries and executables carry explicit private-library RPATHs. The packages
never overwrite `/usr/bin/clang`, system LLVM libraries, or `/etc/ld-musl-*.path`.
No global LD_LIBRARY_PATH is required. For development:

```sh
export ROCM_PATH=/usr/lib/rocm
export HIP_PATH=$ROCM_PATH HIP_PLATFORM=amd
export HIP_CLANG_PATH=$ROCM_PATH/llvm/bin
export HIP_DEVICE_LIB_PATH=$ROCM_PATH/amdgcn/bitcode
export PATH="$ROCM_PATH/bin:$ROCM_PATH/llvm/bin:$PATH"
export CMAKE_PREFIX_PATH="$ROCM_PATH:$ROCM_PATH/llvm${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
```

`KISS_ROCM_PREFIX` overrides the private prefix for isolated build validation.
Use one absolute prefix consistently for **all** ROCm and Strata packages;
packages built with different prefixes must not be mixed. Normal installations
should keep the default. A build still stages exclusively into its DESTDIR.

## GPU targets and scope

The default `gfx1100` is for RX 7900 XT/XTX-class RDNA3. Set
`KISS_ROCM_ARCHS='gfx1100;gfx1201'`, for example, **before building both rocblas
and strata** to produce matching GPU kernels. There is no build-host GPU
probing. Availability in LLVM/ROCm does not imply Strata supports every card:
consult the pinned Strata README and cmake/hip_backend.cmake. Its ordinary HIP
backend assumes wave32 RDNA GPUs. The experimental `gfx906` path additionally
requires `KISS_STRATA_GFX906=ON`; it is not enabled here or covered by RDNA3 tests.

hipBLASLt is deliberately omitted; Strata's optional hipBLASLt lookup is
disabled in its build and its hipBLAS path is used instead.
Tensile is **not** disabled: rocBLAS includes real architecture-specific GEMM
code objects. hipBLAS's optional rocSOLVER API and Fortran clients are disabled.
OpenCL, MIOpen, RCCL, rocSOLVER, profiling tools, and a full ROCm SDK are outside
this package set. COMGR's optional SPIR-V support is disabled.

Sources are release archives for ROCm 7.2.4, not prebuilt binaries. The component
versions differ (e.g. AMD LLVM 22.0.0, rocBLAS 5.2.0, hipBLAS 3.2.0); their KISS
versions identify the coherent ROCm release. Tensile 4.45.0 is a separate
pinned source tarball, commit `1e7797f5b290e828c9ab5c7ce5d4ea3f050b37e3`; the
7.2.4 rocBLAS archive has no `tensile_tag.txt`. Strata 0.2.7 comes from release
tag `v0.2.7`; its native expert ggml sources stay pinned to llama.cpp
`3cf03257f219afbe7334045ff7c6a06ac68c627d`. Both are KISS sources, so Strata
performs no FetchContent download at build time. The package installs `strata`,
`strata-plan`, `strata-gguf`, `strata-dequant`, `strata-device` and
`strata-server` to `/usr/bin`, and the upstream Python server tree (`serve`,
`strata_control`, `strata_cli`, `tools`, `data`, `strata.py`) to
`/usr/lib/strata`. It uses an AVX2 CPU baseline, not `-march=native`. Models
must be supplied separately and are not downloaded by the package.

## musl changes

* LLVM and the HSA/HIP worker threads request at least an 8 MiB stack where
  musl's small default could overflow during compilation/runtime callbacks.
* AMD Clang recognizes KISS's x86_64 musl GCC triples to locate libstdc++ and
  startup files. Host executables target musl; device objects target AMDGPU.
* Private compiler-rt builtins are built for the host musl triple, including
  `_Float16` conversion helpers needed by HIP-generated host code. Compile-only
  `_Float16`/`__bf16` capability probes and the detected bfloat16 definition keep
  the helpers' calling convention consistent with Clang's host code. Sanitizers
  and the other optional compiler-rt runtimes are not included.
* HSA cache flushing uses x86 CPUID for the CLFLUSH line size on musl,
  which has no glibc-specific cache-size `sysconf` keys.
* HIP uses public `CPU_*` affinity operations instead of glibc's private
  `__cpu_mask`/word layout, and handles `/proc/self/exe` without GNU `basename`.
* hipcc uses C++17's libstdc++ filesystem implementation instead of linking
  the obsolete `libstdc++fs.so`.
* rocBLAS drops the same obsolete `-lstdc++fs` link and includes
  `<sys/types.h>` before `<unistd.h>` in its log-stream header.
* The CMake-based recipes pass `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` for
  CMake 4 compatibility; the trees sampled here declare 3.6 and newer, so the
  flag is precautionary, and `amd/device-libs` itself sets no policies.
* HSA ELF headers include their integer types directly rather than relying on
  transitive C++ standard-library includes.
* The HSA loader returns `0` instead of `NULL` from an integer-valued
  symbol lookup; musl defines `NULL` as `nullptr` in C++, which does not
  convert.
* hipBLAS 7.2.4 declares only CXX at project scope, so no Fortran-language
  workaround is needed; Fortran clients are off via
  `-DBUILD_FORTRAN_CLIENTS=OFF`.
* rocBLAS makes ROCtx optional; these recipes disable it while retaining the
  real Tensile GEMM kernels. HIP's profiler-register runtime is also disabled;
  the CppHeaderParser-based profiling-header generation is still performed.
* Strata's `rocm6-blas` patch keeps the real-`rocblas_handle` cuBLAS shim
  gated on hipBLAS before version 3, with an explicit rocBLAS link (not a handle
  cast or a fake workspace). The packaged hipBLAS is 3.2.0, so that branch is not
  selected: `strata` uses hipBLAS 3's own cuBLAS-compatible API, and
  `librocblas.so.5` is still linked for Strata's rocBLAS prefill path.
* Strata's Q2 signed-zero workaround is ungated for HIP in 0.2.7: the
  sign-preserving `__half` branch now applies to every AMDGPU target instead of a
  growing architecture list. The unmodified `hip_q2_zero` test exposed 128/1024
  mismatches on `gfx1100` at the older pin before the workaround reached that
  path; no 0.2.7 rerun of that test is retained.

Additional build/runtime findings and completed validation are recorded in
`VALIDATION.md` next to these recipes (also installed under
`/usr/share/doc/rocm`). Do not equate successful packaging with
GPU/model validation on a different card or kernel.

## Completed validation

All 24 recipes completed fresh native KISS build/archive/install cycles at the
default `/usr/lib/rocm` prefix in a disposable musl build root, without a prefix
override or reuse of the earlier scratch-prefix artifacts. Six audits passed;
all 24 archives were then installed by KISS into a separate native-musl root.
Installed-root host compiler-rt ABI, nine Python imports, HIP, HIPRTC/COMGR and
hipBLAS/rocBLAS GPU smokes passed on RX 7900 XTX (`gfx1100`). The installed
Strata CLI generated 256 raw tokens across three read-only full-model runs.
The earlier scratch-prefix Strata tests recorded 18 PASS and 1 SKIP; they ran
against the pre-0.2.7 pin and were not rerun in the default-prefix build.

See `VALIDATION.md` for archive provenance, retained failures and exact scope.
This is not glibc numerical/logit parity, answer-quality, native tokenizer/server,
long-context, other-GPU or performance validation. Scratch-prefix archives
remain non-relocatable validation artifacts, separate from the fresh build.

## Runtime prerequisites and smoke tests

Use a kernel with amdgpu, DRM render nodes, and CONFIG_HSA_AMD (KFD) enabled,
and the matching AMD GPU firmware. `/dev/kfd` and `/dev/dri/renderD*` must be
accessible to the user (normally through the render/video groups). No udev
permission changes or kernel installation are performed by these recipes.

```sh
/usr/lib/rocm/bin/rocminfo
KISS_ROCM_TEST_ARCH=gfx1100 /usr/share/doc/rocm/smoke-test
strata --help
```

The smoke test first builds a host compiler-rt `_Float16`/`__bf16` ABI
regression with the private Clang, checking all 65,536 bit patterns of both
formats. It then builds and runs a HIP kernel, a HIPRTC/COMGR JIT kernel with
module launch, and a checked 2x2 hipBLAS/rocBLAS SGEMM; it needs a supported,
accessible GPU and the compiler packages. Select
the actual GPU with HIP_VISIBLE_DEVICES if necessary. It is not a model run or
a precision/performance acceptance test. Follow Strata's upstream instructions
for supplying a supported GGUF model and exercising inference. Never use
`HSA_OVERRIDE_GFX_VERSION` to conceal an architecture/kernel mismatch.
