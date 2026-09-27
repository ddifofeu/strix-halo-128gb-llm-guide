# Benchmark methodology

## Purpose

Measure practical local-LLM capacity and throughput on a 128 GB Strix Halo APU, then select a stable daily inference stack for the tested Bosgame M5.

## Final host stack

- Ubuntu 24.04.5 LTS host
- Linux 6.18.7
- upstream in-tree `amdgpu`
- BIOS UMA 512 MiB
- `amdgpu.gttsize=126976`
- `ttm.pages_limit=32505856`
- `amd_iommu=off` for the dedicated performance runs
- zram 31.2 GiB priority 100 plus 4 GiB disk swap priority -2

The older 6.17 / 112 GiB-GTT / external-driver measurements remain in `data/benchmarks.csv` as historical controls and must not be mixed causally with the corrected 6.18.7 stack.

## Final Vulkan benchmark settings

Unless explicitly labeled otherwise:

```text
-ngl 99
-fa on
-lm none
-lzm auto
PP512
TG128
5 repetitions for final backend comparisons
```

The v3.6 harness records Flash Attention, load mode and lazy mode in its result files.

## Capacity validation

The corrected 512 MiB UMA stack was validated with Qwen3 235B IQ2_M (~73 GiB), IQ3_XS (~90 GiB) and IQ3_M (~100 GiB). All three reached inference with zero swap. This establishes a tested capacity through ~100 GiB, not through the entire nominal GTT aperture.

## Userspace A/B

To estimate the effect of the newer userspace Vulkan stack, the same llama.cpp binary and llama/ggml libraries (`d2e54583c`, build 11149) were executed both natively and inside the Fedora 44 `vulkan-radv` toolbox. This holds llama.cpp constant but does not isolate Mesa alone: the Vulkan loader and other userspace libraries also differ.

## Backend A/B

The final Vulkan-vs-ROCm comparison used:

- Fedora 44 base
- llama.cpp build 11206 / `2b129ccfa`
- Qwen3 235B IQ3_M
- `-ngl 99`
- `-fa on`
- PP512 / TG128 / combined

Vulkan tested both `lm=auto` and `lm=none`. ROCm tested the same. ROCm `lm=auto` exhibited pathological TG behavior and is recorded as a compatibility/performance failure mode rather than a normal throughput result.

## Telemetry and interpretation

The benchmark harness records RAM, swap, AMDGPU VRAM/GTT, process RSS/VSZ, VM paging counters, NVMe I/O and temperatures.

Interpretation rules:

- PP/TG are throughput measurements, not model-quality scores.
- Repeated PP differences must exceed run-to-run spread before being treated as meaningful.
- A zero-swap capacity pass is stronger evidence than nominal Vulkan/ROCm addressable-memory size.
- Results from different kernels/driver stacks are not causal UMA A/B tests.
- `VMM: no` reported by ROCm is recorded as an implementation detail; no causal performance claim is made from that flag alone.
