# Bosgame Strix Halo 128 GB Local LLM Guide

**Version:** 1.2 — 27 September 2026  
**Scope:** Large GGUF inference with llama.cpp on a Bosgame M5 / Ryzen AI MAX+ 395 / 128 GB Strix Halo system.

## Executive conclusion

The testing is sufficient to make an operational choice for this machine.

The best tested local-LLM profile is:

```text
BIOS UMA            512 MiB
Kernel              Linux 6.18.7
AMDGPU              upstream in-tree driver
GTT                 126976 MiB
TTM pages           32505856
IOMMU               off for dedicated LLM/performance profile
Userspace           Kyuz0 Fedora 44 vulkan-radv toolbox
Mesa/RADV           26.2.3
llama.cpp            build 11206 / 2b129ccfa
Backend             Vulkan/RADV
GPU layers          99
Flash Attention     on
Load mode           none (no-mmap)
Lazy mode           auto
```

On Qwen3 235B-A22B IQ3_M (~99.95 GiB), this profile delivered **198.53 tok/s PP512, 17.34 tok/s TG128 and 62.84 tok/s combined** in the final Kyuz0 Vulkan run.

The same llama.cpp build with ROCm 10.0 and `load-mode=none` delivered **188.03 PP512, 15.65 TG128 and 57.58 combined**. ROCm `load-mode=auto` showed pathological generation performance at 2.42 tok/s and is not recommended for this workload.

This is enough evidence to stop tuning and move to normal usage. It is a conclusion for this hardware and workload, not a universal Vulkan-vs-ROCm claim.

## 1. What changed from version 1.1

Version 1.1 concluded that 96 GiB fixed UMA was the safest AI-first setting because the old 512 MiB configuration timed out on 73–90 GiB models. That conclusion is superseded.

After moving to Linux 6.18.7, removing the external AMDGPU DKMS path, using the upstream kernel amdgpu, increasing the GTT aperture to 126,976 MiB and TTM pages to 32,505,856, **512 MiB BIOS UMA successfully ran the tested 73, 90 and ~100 GiB GGUFs with zero swap**.

Because multiple stack variables changed together, the experiment does not identify one single fix. It does establish that the old failure was **not an intrinsic 512 MiB UMA capacity limit**.

## 2. Final host configuration

### Hardware

- Bosgame M5
- AMD Ryzen AI MAX+ 395, 16C/32T
- Radeon 8060S / GFX1151
- 128 GB physical RAM
- Samsung 990 PRO 4 TB NVMe

### Linux / memory

- Ubuntu 24.04.5 LTS host
- Linux `6.18.7-061807-generic`
- Upstream in-tree amdgpu
- BIOS UMA: 512 MiB
- Linux-visible RAM: ~124 GiB
- GTT: 126,976 MiB
- TTM page limit: 32,505,856
- Vulkan-reported memory: 127,488 MiB in the Fedora/RADV toolbox
- ROCm-reported VRAM: 126,976 MiB

Performance boot parameters used in the final campaign:

```text
amd_iommu=off amdgpu.gttsize=126976 ttm.pages_limit=32505856
```

`amd_iommu=off` is appropriate only when its DMA-isolation/VFIO trade-offs are acceptable. It is retained here because this is a dedicated measured performance profile.

## 3. Corrected 512 MiB capacity result

Under the corrected host stack, all three large Qwen3 235B quants completed without swap:

| Model | Size | PP512 | TG128 | Min available RAM | Peak GTT | Peak swap |
|---|---:|---:|---:|---:|---:|---:|
| IQ2_M | 73.16 GiB | 163.30 | 19.98 | 38,475 MiB | 75,915 MiB | 0 MiB |
| IQ3_XS | 90.25 GiB | 160.67 | 17.78 | 20,820 MiB | 93,422 MiB | 0 MiB |
| IQ3_M | 99.95 GiB | 156.78 | 17.05 | 10,603 MiB | 103,370 MiB | 0 MiB |

This validates the machine through approximately **100 GiB model size** with BIOS UMA left at 512 MiB.

Do not infer that every model up to the full 124 GiB GTT aperture will work. The tested ceiling is ~100 GiB.

## 4. Loader and Flash Attention tuning

### Load behavior on the native stack

For the ~100 GiB IQ3_M model, `load-mode=auto / lazy=auto` was materially better than forcing `load-mode=none / lazy=off`. The latter increased load time and page-fault activity.

That old comparison changed two variables at once. It should not be read as evidence against no-mmap by itself.

### Flash Attention

A controlled same-invocation A/B/C on the native Vulkan build produced:

| FA mode | PP512 | TG128 | Combined |
|---|---:|---:|---:|
| auto | 146.86 | 16.42 | 57.44 |
| **on** | **150.43** | **16.91** | 57.40 |
| off | 142.33 | 16.24 | 52.91 |

`-fa on` is therefore the explicit benchmark/runtime choice. `off` is clearly inferior on this setup.

### Kyuz0 no-mmap validation

With the final Kyuz0 Vulkan stack, `load-mode=none` and `auto` were effectively tied:

| Vulkan load mode | PP512 | TG128 | Combined |
|---|---:|---:|---:|
| auto | 198.93 | 17.30 | 62.70 |
| **none** | **198.53** | **17.34** | **62.84** |

Kyuz0 recommends Flash Attention plus no-mmap on Strix Halo. Since no-mmap had no measurable throughput penalty here, the final profile uses `-fa on -lm none -lzm auto`.

## 5. TuneD and IOMMU

### TuneD

With FA on and the same model:

| TuneD profile | PP512 | TG128 | Combined |
|---|---:|---:|---:|
| balanced | 154.57 | 17.31 | 58.46 |
| accelerator-performance | 152.22 | 17.29 | 58.42 |

No measurable performance gain was found. `balanced` remains the normal host profile.

### IOMMU

Three IOMMU-off runs averaged approximately:

```text
PP512       162.89 tok/s
TG128        17.13 tok/s
Combined     59.06 tok/s
```

The single IOMMU-on reference was 154.57 / 17.31 / 58.46. The PP increase with IOMMU off reproduced, while TG was about 1% lower. Because the IOMMU-on side was not replicated, this remains a host-specific performance observation rather than a universal recommendation.

## 6. The most important performance result: Fedora 44 / RADV 26.2.3

The cleanest userspace comparison reused the exact same old llama.cpp binary (`d2e54583c`, build 11149) and its llama/ggml libraries, but ran it inside Kyuz0's Fedora 44 `vulkan-radv` toolbox.

Two toolbox runs averaged:

```text
PP512       193.19 tok/s
TG128        17.39 tok/s
Combined     62.505 tok/s
```

The four-run native IOMMU-off reference averaged:

```text
PP512       163.11 tok/s
TG128        17.13 tok/s
Combined     59.04 tok/s
```

That is roughly **+18.4% PP, +1.5% TG and +5.9% combined**. The comparison changes more than Mesa alone (`libvulkan`, libc/libstdc++ and the Fedora userspace also differ), but llama.cpp itself is held constant and the newer RADV/Mesa stack is the dominant GPU-side change.

## 7. Final backend comparison

The final A/B used the same Fedora 44 base and the same llama.cpp build 11206 (`2b129ccfa`).

| Backend | Load | PP512 | TG128 | Combined |
|---|---|---:|---:|---:|
| **Vulkan/RADV** | **none** | **198.53** | **17.34** | **62.84** |
| Vulkan/RADV | auto | 198.93 | 17.30 | 62.70 |
| ROCm 10.0 | none | 188.03 | 15.65 | 57.58 |
| ROCm 10.0 | auto | 187.18 | **2.42** | 39.88 ± 25.85 |

Against stable ROCm none, Vulkan none is approximately:

- +5.6% PP512
- +10.8% TG128
- +9.1% combined

ROCm 10.0 is functional on gfx1151 when `/dev/kfd` is correctly exposed. The direct Podman validation reported one ROCm device, gfx1151, wave size 32 and 126,976 MiB VRAM. The Distrobox interactive session on this Ubuntu host lost KFD permissions, so the ROCm benchmark was executed directly with rootless Podman + crun + `--group-add keep-groups`. This is a container integration issue, not a ROCm device failure.

## 8. Final recommendation

For this Bosgame M5, stop tuning and use:

```text
BIOS UMA:        512 MiB
Kernel:          6.18.7 upstream amdgpu
GTT/TTM:         126976 MiB / 32505856 pages
IOMMU:           off only for the dedicated LLM/perf profile
TuneD:           balanced
Container:       Kyuz0 stable vulkan-radv
Mesa:            RADV 26.2.3 (validated image)
llama.cpp:       current validated Kyuz0 build or newer after regression check
GPU layers:      99
Flash Attention: on
Load mode:       none
Lazy mode:       auto
```

For the tested Qwen3 235B IQ3_M, Vulkan/RADV is the backend to use. There is no practical reason from these measurements to prefer ROCm 10.0 for this workload.

## 9. Reproduction

Kyuz0 toolbox repository:

https://github.com/kyuz0/amd-strix-halo-toolboxes

Stable Vulkan image:

```text
docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv
```

Reference benchmark:

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

The repository benchmark harness v3.6 defaults to the final tuning values.

## 10. What the old UMA campaign still proves

The 512 MiB / 64 GiB / 96 GiB campaign is retained as historical evidence. It correctly documented a severe large-model failure mode under the older stack. What changes is the interpretation:

- The failure was **not** proof that 512 MiB BIOS UMA is inherently incapable of 73–100 GiB models.
- The corrected stack proves that 512 MiB UMA can work cleanly through ~100 GiB on this machine.
- Because kernel, driver provenance, GTT and TTM changed together, the exact fix is still unknown.

This is a useful reminder that Strix Halo capacity is a property of the **whole memory/software stack**, not the BIOS UMA number alone.

## 11. Remaining limitations

- One physical machine.
- One ~100 GiB MoE model for the final Vulkan-vs-ROCm backend comparison.
- No long-context 8K/32K/64K KV-cache characterization in the final profile.
- No power-at-the-wall comparison.
- No isolated experiment separating kernel 6.18.7, upstream AMDGPU, GTT 126976 and TTM 32505856.
- Current validated capacity ends at ~100 GiB.

Those are future research questions, not blockers for choosing the daily stack.
