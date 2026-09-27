# Changelog

## 1.1.0 — 2026-09-27

- Added controlled 512 MiB / 64 GiB / 96 GiB UMA comparison.
- Added 512 MiB UMA runs for Qwen3 8B, Qwen3-Coder-Next, Qwen3 235B IQ2_M and IQ3_XS.
- Added 96 GiB control for Qwen3 235B IQ2_M: 170.09 PP512 / 20.40 TG128, 91.004 s total.
- Documented the 512 MiB large-GTT cliff: 73.16 GiB IQ2_M timed out after 601.178 s with zero swap; 90.25 GiB IQ3_XS timed out with severe reclaim/swap.
- Reframed profile guidance: 96 GiB AI-first, 64 GiB mixed-workstation, 512 MiB host-RAM-first.
- Added three-way throughput and observed-capacity charts.
- Updated Reddit post to incorporate community feedback and the new measurements.

## 1.0.0 — 2026-09-24

- Initial public-shareable guide.
- 64 vs 96 GiB UMA A/B results.
- Qwen3 8B, 30B-A3B, Coder-Next and 235B benchmark data.
- IQ3_M memory-cliff telemetry.
- Vulkan build helper, model downloader and v3.5 benchmark harness.
- Reddit TL;DR and long-form Markdown guide.
