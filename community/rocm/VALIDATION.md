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

All **24 actual recipe builds/stages completed successfully**, and all
**24 current-version KISS archives are built and audited**. LLVM's archive was
packaged from the successful actual recipe stage using an isolated harness of
KISS's own manifest, strip, dependency-fixup, and tar functions, not by repeating
an expensive build merely to manufacture an archive. Stage inventories before
and after packaging agree. The corrected LLVM recipe was subsequently rebuilt
for the real compiler-rt ABI fixes described below and its archive replaced.
The harness/provenance are retained in `$s/package-staged-llvm.py` and
`$s/llvm-archive-provenance.json`; this is not a claim of a full `kiss b`
LLVM build/install cycle or a default-prefix build.

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
* All 47 declared source entries (44 unique files) match KISS's
  `b3sum -l 33` checksums in source order.
* The 24 staged packages own 5,507 non-directory paths without conflicts.
  All 47 symlinks resolve in the staged union. The 127 host executable/shared
  ELFs have no non-musl interpreter, GLIBC symbol versions, glibc libraries,
  or build/stage RPATHs; 75 AMDGPU objects were identified separately.
* All 529 NEEDED edges are reachable through runtime dependency recipes,
  assuming the normal KISS base GCC/musl runtime.
* The 24 archives pass gzip integrity, safe-member, ownership, same-prefix
  payload, symlink-target, and KISS metadata checks. Their 127 host ELFs have
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

## Installed archives in an isolated musl root: PASS

All 24 audited archives were installed with actual `kiss i` into
`$s/archive-install-root`, using `KISS_ROOT` rather than modifying the live
system. Their embedded absolute scratch prefix is unchanged inside the root.
The root contains native base musl, GCC 16.1/libstdc++, binutils, Python and
required DRM/ELF/zlib/zstd libraries, not the host's staged ROCm files or system
LLVM executables. Installed package manifests, file contents, symlink targets
and metadata were verified against the selected archive SHA256s.

KISS deliberately omits `libnuma.la` from its manifest although tar contains it;
its absence after install is recorded. Two `.bat` file modes normalized by
installer umask 022 are also recorded. No content/symlink mismatches remain.
Base inputs, including the GCC `libgcc_s.so` linker script and libdrm GPU-name
database, are recorded in `$s/archive-install-base.json`.

The root runs in a private mount namespace with read-only `/sys` and `/proc`,
existing GPU nodes and a private `/dev/shm`; host GPU permissions and mounts
are unchanged. `LD_LIBRARY_PATH` is unset. The archived Clang, all nine archived
Python prerequisite imports, shipped smoke checks and `strata-device --selftest`
pass. This verifies installed scratch-prefix archives, **not** a default-prefix
installation. Evidence: `$s/archive-install-result.json`,
`$s/archive-root-smoke.{log,status}` and `$s/archive-root-{enter,namespace}.sh`.
The inner shell explicitly sets `-eu`; an early wrapper that incorrectly
continued after a failed check was rejected, preserved, and not counted as PASS.

## Host compiler-rt ABI regression: PASS

The installed-root check exposed real `_Float16` and `__bf16` ABI defects.
Function-only CMake executable-link probes failed for lack of `main`, falsely
reporting unsupported types in the runtimes build. Its builtins then used an
integer argument where Clang-generated host code uses an SSE register.
The production LLVM patch uses the existing `try_compile_only` helper for both
probes and defines `COMPILER_RT_HAS_BFLOAT16` when that capability is detected
(the upstream CMake omitted that definition). LLVM/compiler-rt was genuinely
rebuilt, repackaged and reinstalled after these changes.

The shipped `compiler-rt-smoke.c`, linked by private Clang with
`--rtlib=compiler-rt`, checks all 65,536 bit patterns of each 16-bit format:
float extensions, half-to-double conversion, exactly representable round trips,
NaN classification on truncation, and volatile half addition. It passes using
the corrected archive. A negative control linked against the intermediate
half-correct/bfloat-broken builtins fails at bfloat input zero; the regression
was not weakened to hide the ABI failure. This is not comprehensive rounding,
libm, or GPU precision validation. Evidence: `$s/compiler-rt-shipped*`,
`$s/llvm-half-abi-*` and the superseded artifacts under
`$s/before-float16-fix` / `$s/after-float16-only-fix`.

## GPU smoke tests: PASS

After the host compiler-rt regression, the shipped `smoke-test` runs three
real GPU checks:

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
The latest checks use installed stripped archives and installed docs in the
disposable musl root, with no access to the original host prefix or stage.
Earlier staged/extracted smoke evidence is retained separately.

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

## Full-model CLI inference: PASS, staged and installed archive binaries

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

The reference Arch/glibc chroot was used only for CPU encoding/decoding with
its existing Python regex module. **Inference executables, HIP/BLAS libraries
and loaders were native musl builds, never run in that reference chroot.** Shard inspection reported no unknown tensor
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

### Longer, multiple-prompt installed-root checks

The stripped archive installed by KISS was also run inside the disposable
musl root, with the existing shards, pack, MTP and profile mounted read-only.
The driver checks read-only mount flags, exit status, echoed prompt IDs, output
ID ranges and token counts. It completed three independent CLI invocations
using the same conservative settings as above:

| Raw prompt | Generated tokens | Result |
| --- | ---: | --- |
| `The capital of France is` | 128 | exit 0; first 16 IDs match the earlier staged/archive completion |
| `One plus one equals` | 64 | exit 0; token range/count checks pass |
| `Write a short Python function that adds two integers:` (with trailing newline) | 64 | exit 0; token range/count checks pass |

The 128-token France output extends into a coherent Paris description, ending
`The city is divided into`. These are raw-token completions, without a chat
template, and are **not answer-quality acceptance tests**: the arithmetic case
initially says `three`, then reasons that the statement is mathematically
incorrect; the Python case enters reasoning rather than completing a function
within the 64-token limit. No mathematical/code correctness claim is made.

CPU tokenizer round trips validate the input strings; output decoding uses the
same existing reference tokenizer. Asset size/inode/time metadata is unchanged
after the read-only runs, and no asset mounts escape into the host namespace
(this is not a full model-content hash). Evidence:
`$s/archive-root-models.{log,status}`, `$s/archive-root-models-decoded.json`,
`$s/archive-model-{prompts,assets-before,assets-after}.json`, and
`$s/archive-install-root/validation/models/`. These 256 generated tokens are
longer than the original smoke, but not sustained server or long-context
validation. Timing diagnostics are not benchmarks; no logits were compared.

## Remaining limitations

* A complete default-prefix build and installation/runtime test.
* Numerical comparison with the reference, native tokenizer/server integration,
  and sustained server/long-context testing.
  This recipe packages Strata's native CLI tools, not its Python server venv.
* Other GPUs, multi-GPU operation, and meaningful performance measurement.
* Full ROCm SDK, OpenCL, MIOpen, RCCL, rocSOLVER, hipBLASLt, profiler tools,
  and the optional profiler-register runtime are intentionally outside scope.
