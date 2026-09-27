# Changelog

## 1.2.0 — 2026-09-27

- Reversed the old 96 GiB-UMA recommendation after corrected-stack testing showed that **512 MiB BIOS UMA can run the tested 73–100 GiB GGUFs with zero swap**.
- Documented the corrected host stack: Linux 6.18.7, upstream in-tree AMDGPU, GTT 126,976 MiB and TTM pages 32,505,856.
- Added controlled Flash Attention results; `-fa on` is now the explicit performance default.
- Added TuneD comparison; `accelerator-performance` showed no measurable advantage over `balanced`.
- Added IOMMU testing; `amd_iommu=off` improved PP on this host but is documented as a dedicated performance-profile choice with security/virtualization trade-offs.
- Added Kyuz0 Fedora 44 / Mesa RADV 26.2.3 userspace validation. With the same llama.cpp build, PP512 improved from a 163.11 tok/s native mean to 193.19 tok/s in the toolbox.
- Added final Vulkan-vs-ROCm 10.0 comparison on llama.cpp build 11206 (`2b129ccfa`). Vulkan/RADV `lm=none` achieved 198.53 PP512 / 17.34 TG128 / 62.84 combined versus ROCm `lm=none` at 188.03 / 15.65 / 57.58.
- Documented pathological ROCm `load-mode=auto` TG behavior (2.42 tok/s) on the ~100 GiB IQ3_M workload.
- Updated the final recommendation to **512 MiB UMA + corrected large-GTT host stack + Kyuz0 stable Vulkan/RADV + FA on + load none + lazy auto** for this machine.
- Updated benchmark harness to v3.6 with explicit Flash Attention recording and final-profile defaults.

## 1.1.0 — 2026-09-27

- Added controlled 512 MiB / 64 GiB / 96 GiB UMA comparison on the earlier stack.
- Added 512 MiB UMA runs for Qwen3 8B, Qwen3-Coder-Next, Qwen3 235B IQ2_M and IQ3_XS.
- Added 96 GiB control for Qwen3 235B IQ2_M: 170.09 PP512 / 20.40 TG128, 91.004 s total.
- Documented the older-stack 512 MiB large-GTT cliff.
- Added three-way throughput and observed-capacity charts.

## 1.0.0 — 2026-09-24

- Initial public-shareable guide.
- 64 vs 96 GiB UMA A/B results.
- Qwen3 8B, 30B-A3B, Coder-Next and 235B benchmark data.
- IQ3_M memory-cliff telemetry.
- Vulkan build helper, model downloader and v3.5 benchmark harness.
