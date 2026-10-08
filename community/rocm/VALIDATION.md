# Validation record: ROCm 6.4.3 HIP compute and Strata on KISS/musl

## Scope and environment

This is an x86_64 source port of the HIP compute subset, not the entire ROCm
SDK. The validated GPU is an AMD Radeon RX 7900 XTX, `gfx1100`, wave32. A
`gfx1036` integrated GPU was enumerated but was not compute-tested. There is
no other-card, multi-GPU, glibc numerical-parity, or performance guarantee.

The native validation host reports `x86_64-pc-linux-musl`, GCC 16.1.0,
system Clang 22.1.8, CMake 4.4.3, and Python 3.14.7. ROCm uses its own AMD
LLVM/Clang 19. The system LLVM, live `/usr`, libc, loader configuration, GPU
permissions, models, and existing Arch/glibc chroot were not modified.
No gcompat or glibc runtime libraries are used by the tested executables.

All compute packages used a single absolute validation prefix:

```sh
s=/root/.cache/rocm-kiss-validation
export KISS_ROCM_PREFIX="$s/prefix"
```

Explicit RPATHs select the private libraries; GPU runs unset
`LD_LIBRARY_PATH` and select `HIP_VISIBLE_DEVICES=0`. There was no
`HSA_OVERRIDE_GFX_VERSION` or other architecture-override workaround.

**These scratch-prefix archives are validation artifacts, not distributable
packages for the default `/usr/lib/rocm` prefix.** A default-prefix build and
installation/runtime test remain outstanding. Do not mix prefixes or move
these binaries and expect their embedded paths to relocate.

## Recipe and archive coverage

The set contains 24 new recipes: numactl; rocm-cmake, rocm-core, rocm-llvm,
rocm-device-libs, rocm-comgr, rocm-hipcc, rocm-runtime, rocm-hip, rocminfo;
hipblas-common, rocblas, hipblas; strata and the rocm documentation/meta-package;
and python-msgpack, python-joblib, python-rich, python-pygments,
python-markdown-it-py, python-mdurl, python-poetry-core, python-ply,
python-cppheaderparser.

All **24 actual recipe builds/stages completed successfully**. There are
**23 current-version KISS archives built and audited**; only `rocm-llvm`
lacks a validated KISS archive. The actual LLVM recipe compiled and installed
into a staged DESTDIR, including musl compiler-rt builtins. It has **not** been
rebuilt through `kiss b` to produce and validate its archive. Successful LLVM
compilation is not completed all-package archive validation.

Selected archives are recorded in `$s/archive-audit-details.json`. They are
in the normal cache and the isolated `$s/kiss-cache-root/kiss/bin` cache;
build queue logs and exit statuses are retained under `$s`. Three earlier
support archives (`rocm-cmake`, `rocm-core`, `hipblas-common`) targeted the
default prefix. Those packages were rebuilt in the isolated cache, and the
selected compute archives now match the single staged validation prefix.
The older default-prefix copies are not part of this validated stack.

Forced, explicitly named validation builds bypass dependency installation;
`KISS_PROMPT=0` prevents the final install prompt. The staged dependency prefix
and Python site supply prerequisites without installing these new packages
into the live host.

Final checks:

* All 24 recipes pass shell syntax, executable-script, version, source/count,
  dependency availability, and acyclic dependency-graph checks.
* All 46 declared source entries (43 unique files) match KISS's
  `b3sum -l 33` checksums in source order.
* The 24 staged packages own 5,506 non-directory paths without conflicts.
  All 47 symlinks resolve in the staged union. The 127 host executable/shared
  ELFs have no non-musl interpreter, GLIBC symbol versions, glibc libraries,
  or build/stage RPATHs; 75 AMDGPU objects were identified separately.
* All 529 NEEDED edges are reachable through runtime dependency recipes,
  assuming the normal KISS base GCC/musl runtime.
* The 23 archives pass gzip integrity, safe-member, ownership, same-prefix
  payload, symlink-target, and KISS metadata checks. Their 23 host ELFs have
  clean dynamic metadata matching the corresponding staged files, and their
  75 AMDGPU objects remain present. Archived recipe metadata matches the
  current recipes.

Evidence is retained in `$s/recipe-check.log`, `$s/source-hash-audit.json`,
`$s/stage-audit.json`, `$s/dependency-audit.json`, `$s/archive-audit.json`,
`$s/archive-stage-elf-comparison.json`, and `$s/archive-recipe-comparison.json`.
These are isolated build/artifact checks, not a default-prefix install test.

rocBLAS deliberately has `nostrip`: the host GNU strip cannot process its
AMDGPU `.hsaco` objects. Strata's stripped KISS binary was also exercised in
real model generation, not just inspected.

## GPU smoke tests: PASS

The shipped `smoke-test` runs three real GPU checks:

* HIP `add_one` over 1024 elements, checking every result.
* HIPRTC compilation through COMGR, module loading, and a JIT `add_two` kernel,
  checking every result.
* hipBLAS/rocBLAS 2x2 SGEMM, checking results `23, 34, 31, 46`.

The isolated smoke test uses the staged docs and the private compiler/runtime:

```sh
doc="$s/stage/rocm/usr/share/doc/rocm"
KISS_ROCM_PREFIX="$s/prefix" KISS_ROCM_TEST_ARCH=gfx1100 \
    HIP_VISIBLE_DEVICES=0 "$doc/smoke-test"
```

After a normal default-prefix installation, use
`/usr/share/doc/rocm/smoke-test` without `KISS_ROCM_PREFIX`.

`rocminfo`, Strata help/device enumeration, and `strata-device --selftest`
also ran successfully. The device selftest checks allocation, not inference.
For the isolated run, executables and docs come from the staged/extracted
package paths rather than the live `/usr`.

## Strata kernel/parity tests: 18 PASS, 1 SKIP

The main HIP suite has 13 passes: `hip_prefill_gemm`,
`hip_gemm_f16_io_parity`, `hip_q2_zero`, `hip_expert_cache_staging`,
`hip_intrinsics`, `hip_handoff`, `hip_mapped_alias`, `hip_native_qsa_score`,
`hip_prefill_native_batch`, `hip_gdn_rec_head`, `hip_prefill_wmma_gemm_parity`,
`hip_router_fast`, and `hip_prompt_attn_wmma`.
`hip_prefill_hcd_exact_parity` explicitly exits 77 and is a **skip**, not a pass.

Five additional parity tests pass: `dequant_s2_parity`, `s2_gemv_parity`,
`iq_multi_parity`, `native_grouped_parity`, and `shared_expert_parity`.
The tests and their acceptance thresholds were not weakened.
The initial `hip_q2_zero` failure is preserved in the initial-suite logs; the
production kernel's existing signed-zero workaround was extended for
`gfx1100`/HIP < 7 and the same test passes after rebuilding.

These results do not establish complete full-model numerical parity with a
glibc build. Test drivers/logs are `$s/test-strata-hip.sh`,
`$s/test-strata-extra.sh`, and `$s/strata-{hip,extra}-tests*.log`.

## Short full-model inference: PASS, staged and stripped archive binaries

Strata is pinned to `d5ea7133741e67743c0e886bb426c0ce8d69cf6c`, also the
commit in the user's known-good Arch/glibc Strata tree. Its native expert ggml
source is pinned to `3cf03257f219afbe7334045ff7c6a06ac68c627d`.

The test reused these existing assets read-only; no model was downloaded,
converted, or repacked:

* The two `Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_XXS` GGUF shards under
  `/root/progs/llama/GSQ-RCO-IQ3_XXS-abliterated/IQ3_XXS` (about 70.9 GiB total).
* Prepared pack `/root/root.x86_64/root/Strata-data/packs/iq3_xxs`.
* MTP assets `/root/root.x86_64/root/Strata-data/mtp/rt` and the reference
  tree's existing `data/expert-profile.bin`.

The chroot was used only for CPU tokenization with its existing Python regex
module. **The inference executable, HIP/BLAS libraries, and loader were native
musl builds outside the chroot.** Shard inspection reported no unknown tensor
types or out-of-range geometry before inference was attempted.

Settings included native projections/PLE, `--expert-cache auto`,
`--mmap-experts`, `--max-context 4096`, `--kv int8`, `--prefill auto`,
`--spec 4 --spec-min-p 0.5 --mtp ...`, `--adapt-every 0 --pcie-frac 0`,
`--vram-reserve-mib 1024`, and `--max-new 16`.
Native IQ packs require speculation and prefill; the first attempt without
speculation exited 2 at the guard, and that failure was retained.

Prompt: `The capital of France is` (IDs `760 6511 314 9338 369`).
Both the staged executable and the stripped executable extracted from the
Strata KISS archive exited 0 and produced identical 16-token output:

> Paris, which is also the country's most populous city and a major European hub

Output IDs: `11751 11 864 369 1048 279 3046 579 1379 91188 3177 321 264 3478 7277 18156`.

Evidence is retained in `$s/iq3-model*`, `$s/iq3-archive*`,
`$s/test-iq3-model.sh`, and `$s/test-iq3-archive.sh`.
The speculative CLI path left `--dump-logits` empty, so no finite-logit or
logit-level parity claim is made. The two musl binaries agreeing on this short
completion is not glibc parity. Timings from a 16-token smoke run are not a
benchmark; placement was deliberately conservative, not the optimized chroot
server configuration.

## Remaining limitations

* LLVM KISS archive validation and a default-prefix installation/runtime test.
* Longer/multiple-prompt inference, numerical comparison with the reference,
  tokenizer/server integration, and sustained server/long-context testing.
  This recipe packages Strata's native CLI tools, not its Python server venv.
* Other GPUs, multi-GPU operation, and meaningful performance measurement.
* Full ROCm SDK, OpenCL, MIOpen, RCCL, rocSOLVER, hipBLASLt, profiler tools,
  and the optional profiler-register runtime are intentionally outside scope.
