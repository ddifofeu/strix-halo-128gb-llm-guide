# Bosgame Strix Halo 128 GB — Local LLM Guide

A measured, reproducible guide for running large GGUF models on a **128 GB AMD Strix Halo** system, tested on a Bosgame M5 with a Ryzen AI MAX+ 395 / Radeon 8060S.

> **Final tested conclusion (27 Sep 2026):** on this machine, the best overall local-LLM configuration is **512 MiB BIOS UMA + the corrected Linux 6.18.7/upstream-amdgpu large-GTT setup + Kyuz0's stable Fedora 44 `vulkan-radv` toolbox + Flash Attention on + no-mmap (`load-mode=none`) + lazy mode auto**. This configuration runs the tested **Qwen3 235B IQ3_M (~99.95 GiB)** without swap and is faster than the tested ROCm 10.0 path on the same llama.cpp commit.

This supersedes the earlier repo conclusion that 96 GiB fixed UMA was required for the ~100 GiB model class. The old 512 MiB failures were real, but they occurred on a different, confounded software/kernel/GTT stack and therefore were **not an intrinsic 512 MiB UMA capacity limit**.

## Final profile for this Bosgame M5

| Layer | Final tested setting |
|---|---|
| BIOS UMA | **512 MiB** |
| Kernel | **6.18.7**, upstream in-tree `amdgpu` |
| GTT | `amdgpu.gttsize=126976` |
| TTM pages | `ttm.pages_limit=32505856` |
| IOMMU | `amd_iommu=off` for the dedicated benchmark/performance profile |
| Container/userspace | **Kyuz0 `vulkan-radv`**, Fedora 44 |
| Mesa/RADV | **26.2.3** in the validated toolbox image |
| llama.cpp | build **11206**, commit `2b129ccfa` for the final backend comparison |
| Backend | **Vulkan / RADV** |
| GPU layers | `-ngl 99` |
| Flash Attention | **`-fa on`** |
| Load mode | **`-lm none`** (no-mmap) |
| Lazy mode | **`-lzm auto`** |

`amd_iommu=off` removes DMA isolation and can affect VFIO/passthrough and security assumptions. It is a performance-profile choice, not a universal desktop recommendation. Kyuz0's broader guidance uses an IOMMU passthrough profile; this host measured a reproducible PP improvement with IOMMU disabled, but only one IOMMU-on reference run was collected.

## Why this conclusion changed

The first campaign compared 512 MiB, 64 GiB and 96 GiB BIOS UMA on Linux 6.17 with a different AMDGPU stack and a 112 GiB GTT aperture. Under that stack, 512 MiB UMA hit a severe practical cliff on 73–90 GiB models and 64 GiB UMA failed on the ~100 GiB IQ3_M model.

The corrected campaign changed several variables together: Linux 6.18.7, external DKMS removal in favor of upstream `amdgpu`, GTT from 114,688 to 126,976 MiB, and TTM pages from 30,720,000 to 32,505,856. With BIOS UMA still at **512 MiB**, all three large Qwen3 235B quants tested successfully with zero swap:

| Model | GGUF | PP512 | TG128 | Result | Peak swap |
|---|---:|---:|---:|---|---:|
| Qwen3 235B IQ2_M | 73.16 GiB | 163.30 | 19.98 | PASS | 0 MiB |
| Qwen3 235B IQ3_XS | 90.25 GiB | 160.67 | 17.78 | PASS | 0 MiB |
| Qwen3 235B IQ3_M | 99.95 GiB | 156.78 | 17.05 | PASS | 0 MiB |

These runs establish capacity through ~100 GiB on this corrected stack. They do **not** isolate which of kernel, driver, GTT or TTM changes fixed the old cliff.

## The biggest performance gain: newer RADV userspace

The strongest performance result came from running the **same llama.cpp binary** (`d2e54583c`, build 11149) inside Kyuz0's Fedora 44 `vulkan-radv` toolbox. The llama/ggml libraries stayed from the host build while the container supplied the newer userspace Vulkan stack.

For Qwen3 235B IQ3_M:

| Stack | PP512 | TG128 | Combined |
|---|---:|---:|---:|
| Native Ubuntu/RADV, IOMMU off, same llama.cpp | 163.11 | 17.13 | 59.04 |
| Fedora 44 / Mesa RADV 26.2.3, same llama.cpp | **193.19** | **17.39** | **62.51** |

That is approximately **+18.4% PP**, **+1.5% TG** and **+5.9% combined** with the same llama.cpp build. This is a userspace-stack comparison rather than a pure Mesa-only A/B, but RADV/Mesa is the dominant changed GPU component.

## Final Vulkan vs ROCm comparison

The final backend test used the **same llama.cpp commit** (`2b129ccfa`, build 11206), Fedora 44 base, Qwen3 235B IQ3_M, `-ngl 99`, Flash Attention on and five repetitions.

| Backend / load mode | PP512 | TG128 | Combined | Notes |
|---|---:|---:|---:|---|
| **Vulkan/RADV, `lm=none`** | **198.53** | **17.34** | **62.84** | Final recommended profile |
| Vulkan/RADV, `lm=auto` | 198.93 | 17.30 | 62.70 | Effectively tied with `none` |
| ROCm 10.0, `lm=none` | 188.03 | 15.65 | 57.58 | Stable but slower |
| ROCm 10.0, `lm=auto` | 187.18 | 2.42 | 39.88 ± 25.85 | Pathological TG behavior; avoid for this workload |

On this ~100 GiB MoE model, the recommended Vulkan result is about **+5.6% PP**, **+10.8% TG** and **+9.1% combined** versus the stable ROCm `lm=none` run.

This is a conclusion for **this hardware + model + current stacks**, not a claim that Vulkan is universally faster than ROCm on every Strix Halo workload.

## Runtime tuning results

### Flash Attention

Controlled same-invocation testing showed `-fa on` was the best PP/TG choice. `-fa off` was clearly worse. Keep Flash Attention explicitly enabled rather than relying on `auto` for benchmark/reproducibility work.

### Load mode

On the current Kyuz0 Vulkan stack, `load-mode=none` and `auto` were effectively tied. Because Kyuz0 recommends Flash Attention + no-mmap on Strix Halo and `none` did not cost throughput here, the final profile uses:

```text
-fa on
-lm none
-lzm auto
```

Do not combine this conclusion with the old `none/off` experiment: forcing `lazy-mode=off` was a separate change and performed worse on the older native stack.

### TuneD

`accelerator-performance` did not produce a measurable gain over `balanced` on this Bosgame. Keep `balanced` for normal use; there is no evidence from these measurements that the accelerator profile is needed.

### IOMMU

With the current native Vulkan stack, three IOMMU-off runs averaged roughly 162.89 PP / 17.13 TG / 59.06 combined versus one IOMMU-on reference at 154.57 / 17.31 / 58.46. The PP gain reproduced across the off runs, while TG was slightly lower. Because the on side was not replicated, treat this as a host-specific performance observation rather than a universal rule.

## Reproduce the recommended userspace

The validated stable toolbox comes from:

- https://github.com/kyuz0/amd-strix-halo-toolboxes
- image: `docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv`

On this Ubuntu host, Distrobox 1.8.2.5 was required for reliable container setup.

Example benchmark inside `llama-vulkan-radv`:

```bash
/usr/bin/llama-bench \
  -m /path/to/Qwen_Qwen3-235B-A22B-Instruct-2507-IQ3_M-00001-of-00003.gguf \
  -ngl 99 \
  -lm none \
  -lzm auto \
  -fa on \
  -pg 512,128 \
  -r 5
```

The updated `scripts/strix-halo-bench.sh` defaults to these final Vulkan tuning values and records Flash Attention alongside load/lazy mode.

## Historical UMA findings: keep, but do not generalize

The old 512 MiB / 64 GiB / 96 GiB results remain useful evidence about the **older** stack. They show that the software/kernel memory path matters enormously. They no longer support the statement that large fixed UMA is inherently required for 73–100 GiB GGUFs.

The fair statement is now:

> On this Bosgame M5, **512 MiB BIOS UMA can run GGUF models through ~100 GiB when paired with the corrected Linux 6.18.7/upstream-amdgpu large-GTT configuration**. The previous 512 MiB failures were stack-specific and the exact corrective variable was not isolated.

## Benchmark files

- `data/benchmarks.csv` — original UMA campaign
- `data/corrected-capacity.csv` — corrected 512 MiB capacity validation
- `data/backend-comparison.csv` — final Vulkan/userspace/ROCm comparison
- `scripts/strix-halo-bench.sh` — v3.6 benchmark harness, defaulting to FA on / load none / lazy auto
- `docs/GUIDE.md` — detailed findings and caveats
- `docs/METHODOLOGY.md` — methodology and interpretation rules

## Bosgame M5 monitoring and fan tools

The repository now also contains the two host tools used during the Strix Halo tuning campaign:

- **tools/halo-top/** — read-only Strix Halo telemetry, memory-pressure and LLM bottleneck monitor with CSV/JSONL logging.
- **tools/bosgame-m5-fans/** — guarded CLI/GUI fan control for the three channels exposed by the community ec_su_axb35 driver, with timed manual tests and automatic restore behavior.
- **docs/M5-TOOLS.md** — installation and first-use guide for both tools.

The fan tool is a custom frontend, not an official Bosgame utility. Its installer fetches the upstream GPL-2.0 EC driver at a pinned commit; the frontend and halo-top remain MIT-licensed parts of this repository.

## Important limitations

- One physical Bosgame M5 / Ryzen AI MAX+ 395 / 128 GB machine was measured.
- The corrected 512 MiB success changed kernel, AMDGPU provenance, GTT and TTM together. The exact root cause of the old failure is not isolated.
- The final Vulkan-vs-ROCm comparison is for Qwen3 235B IQ3_M and should not be generalized to every model, quant or context length.
- PP512/TG128 are synthetic throughput measurements, not task-quality scores or long-context end-to-end latency.
- The current validation ceiling is **~100 GiB GGUF**, not the full nominal 124 GiB GTT aperture.
- IOMMU-off has security and virtualization trade-offs.

## License

MIT for scripts and documentation in this repository. Model licenses remain those of their respective publishers.
