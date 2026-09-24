# Suggested Reddit title

**Bosgame / Strix Halo 128 GB local LLM tuning: 96 GB UMA lets a ~100 GB Qwen3 235B GGUF run at ~17 tok/s**

# Compact TL;DR post

I benchmarked a 128 GB Bosgame Strix Halo (Ryzen AI MAX+ 395 / Radeon 8060S) on Ubuntu with current llama.cpp Vulkan/RADV.

**Main finding:** if this is primarily an LLM box, set BIOS to **`UMA_SPECIFIED = 96G`**, not 64G. With 64G UMA, Qwen3 235B IQ3_M (~100 GiB GGUF) filled ~65 GiB VRAM, spilled ~39 GiB into GTT, drove Linux into heavy reclaim/swap and still hadn't reached inference after 600 s. With 96G UMA, the exact same model used ~98 GiB VRAM + ~5.7 GiB GTT, zero meaningful swap, and ran at **~166 tok/s PP512 / 17.05 tok/s TG128**.

96G UMA did **not** materially hurt the smaller models I retested:

- Qwen3 30B-A3B Q4_K_M: **~85.5 tok/s**
- Qwen3-Coder-Next Q4_K_M: **~57.5 tok/s**
- Qwen3 8B Q4_K_M: **~41.4 tok/s**
- Qwen3 235B IQ3_XS (~90 GiB): **~18.1 tok/s**
- Qwen3 235B IQ3_M (~100 GiB): **~17.1 tok/s**

My current defaults: **Vulkan/RADV, `-ngl 99`, load-mode auto, lazy-mode auto, zram higher priority than disk swap**. 64G UMA is still a reasonable mixed-workstation choice if you need ~62 GiB host RAM and don't care about ~100 GiB GGUFs; 96G leaves Linux only ~30 GiB.

Caveats: one machine; these are llama-bench PP512/TG128 throughput numbers, not quality scores or long-context tests. My test host also had a large GTT kernel setting; current kernel docs mark `amdgpu.gttsize` deprecated, so don't copy it blindly.

Repo includes benchmark CSV, graphs, a telemetry harness, model downloader, Vulkan build script and the longer guide.
