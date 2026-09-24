# Benchmark methodology

## Purpose

Measure real local-LLM throughput and the practical memory boundary of a 128 GB Strix Halo APU using llama.cpp/Vulkan.

## Software

- Ubuntu 24.04.5 LTS
- Linux 6.17.0-35-generic
- llama.cpp build 11149, commit `d2e54583c`
- Vulkan/RADV GFX1151

## Benchmark settings

Unless stated otherwise:

```text
-ngl 99
PP512
TG128
3 repetitions
load-mode auto
lazy-mode auto
```

`--capacity` in the supplied harness uses one combined llama-bench invocation so very large models are loaded only once.

## Telemetry

The v3.5 harness records:

- minimum Linux `MemAvailable`
- peak swap
- peak AMDGPU VRAM usage
- peak AMDGPU GTT usage
- llama process virtual/RSS measurements
- `/proc/vmstat` page-fault / swap activity
- NVMe diskstats deltas
- CPU/GPU/NVMe temperatures

## A/B rules

The critical 64 vs 96 GiB UMA comparison kept the following constant:

- model and quantization
- llama.cpp build
- Vulkan backend
- `-ngl 99`
- PP512/TG128
- timeout
- load/lazy mode within each paired test

Only BIOS fixed UMA changed.

## Interpretation cautions

- Page cache can make subsequent model loads faster; throughput after load is the more stable comparison.
- `free` and `available` are not equivalent; low `free` with high `available` is normal after reading large GGUF files.
- Vulkan's reported addressable heap can exceed physical RAM because it includes GPU virtual/GTT address space.
- Synthetic PP/TG throughput is not quality, TTFT at long contexts, or full chat latency.
