# v1.0.0 — Strix Halo 128 GB Local LLM Guide

First frozen public release of the measured Bosgame / AMD Strix Halo 128 GB local-LLM tuning guide.

## Highlights

- Reproducible llama.cpp Vulkan benchmark harness with RAM, swap, VRAM, GTT and VM telemetry.
- Measured 64 GiB vs 96 GiB fixed UMA behavior on a Ryzen AI MAX+ 395 / Radeon 8060S system.
- Qwen3 235B IQ3_M (~100 GiB) changed from a >600 s memory-thrashing timeout at 64 GiB UMA to a clean **165.9 tok/s PP512 / 17.05 tok/s TG128** run at 96 GiB UMA.
- Qwen3 30B-A3B measured ~85.5 tok/s TG128.
- Qwen3-Coder-Next measured ~57.5 tok/s TG128.
- Qwen3 235B IQ3_XS measured ~18.1 tok/s TG128 at 96 GiB UMA.
- Recommended AI-first profile: **96 GiB UMA + Vulkan/RADV + `-ngl 99` + load-mode auto + lazy-mode auto**.
- 64 GiB UMA remains a sensible mixed-workstation profile when ~100 GiB GGUFs are not required.

## Assets

- **DOCX** — shareable long-form guide with benchmark charts.
- **ZIP** — frozen repository source for v1.0.0.
- **SHA256SUMS.txt** — checksums for the attached release artifacts.

These measurements are throughput/capacity results, not model-quality rankings. See `docs/METHODOLOGY.md` for test details and limitations.
