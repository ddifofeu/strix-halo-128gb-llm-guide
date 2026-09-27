# Bosgame Strix Halo 128 GB Local LLM Guide

**Version:** 1.1 — 27 September 2026  
**Scope:** Large GGUF inference with llama.cpp/Vulkan on a Bosgame M5-class 128 GB Strix Halo system.

## Executive summary

The three-way **512 MiB / 64 GiB / 96 GiB UMA** experiment establishes a more useful rule than simply “more UMA is better.”

On this tested 128 GB Ryzen AI MAX+ 395 system:

- **512 MiB UMA** maximized host-visible RAM (~124 GiB) and delivered essentially the same generation throughput as 96 GiB UMA on 4.7–45 GiB models. However, Qwen3 235B IQ2_M (~73.16 GiB) failed to reach inference after 601 seconds even with zero swap, and IQ3_XS (~90.25 GiB) entered severe reclaim/swap and timed out.
- **64 GiB UMA** retained ~62 GiB for Linux and successfully ran the 73 and 90 GiB model classes, but Qwen3 235B IQ3_M (~100 GiB) crossed a severe GTT/reclaim cliff and never reached inference within 600 seconds.
- **96 GiB UMA** retained ~30 GiB for Linux and cleanly ran the tested 73–100 GiB models while leaving small/mid-size throughput effectively unchanged.

Therefore, for an **LLM-first 128 GB Strix Halo workstation, 96 GiB `UMA_SPECIFIED` is the best tested overall profile**. For a mixed workstation, 64 GiB remains a strong compromise. 512 MiB is best understood as a host-RAM-first profile for smaller/medium models, not as a universal large-LLM optimization.

These measurements describe throughput and memory behavior, not model quality or precision-per-GiB.

## 1. Test platform

- Bosgame M5 / AMD Ryzen AI MAX+ 395
- 128 GB physical RAM
- Radeon 8060S integrated GPU, GFX1151
- Ubuntu 24.04.5 LTS
- Kernel 6.17.0-35-generic
- RADV Vulkan backend
- llama.cpp build 11149 (`d2e54583c`)
- Vulkan device reported as UMA-capable
- No full system ROCm installation was required for these results

### Test-host memory parameters

The benchmark host had a large GTT aperture configured:

```text
amdgpu.gttsize=114688
ttm.pages_limit=30720000
```

This is part of the test description, **not a blanket recommendation**. Current Linux kernel docs mark `amdgpu.gttsize` deprecated. The experiment did not isolate either boot parameter.

## 2. BIOS profiles tested

### 512 MiB UMA — host-RAM-first

Observed after reboot:

```text
Linux-visible RAM:       ~124 GiB
Fixed VRAM/UMA:             512 MiB
GTT aperture:            114,688 MiB
Vulkan addressable:      115,200 MiB
```

This profile performed very well on 4.68 and 45.09 GiB models, but large GTT-backed allocations became impractical by the 73.16 GiB class.

### 64 GiB UMA — mixed workstation

```text
Linux-visible RAM:       ~62 GiB
Fixed VRAM/UMA:          65,536 MiB
GTT aperture:            114,688 MiB
Vulkan addressable:      180,224 MiB
```

This profile ran through the ~90 GiB model class, but the ~100 GiB IQ3_M model crossed a severe reclaim cliff.

### 96 GiB UMA — AI-first recommendation

```text
iGPU Configuration:      UMA_SPECIFIED
UMA Frame Buffer Size:   96G

Linux-visible RAM:       ~30 GiB
Fixed VRAM/UMA:          98,304 MiB
GTT aperture:            114,688 MiB
Vulkan addressable:      212,992 MiB
```

This was the best tested profile for large-model inference.

### Why not BIOS Auto?

`Auto` was not benchmarked. A shareable guide should not claim it is equivalent to a fixed 512 MiB, 64 GiB or 96 GiB reservation.

## 3. Build llama.cpp with Vulkan

Upstream llama.cpp documents the `GGML_VULKAN=ON` build option and states that `-ngl 99` should offload all layers for most models.

```bash
sudo apt update
sudo apt install -y \
  git build-essential cmake ninja-build \
  libvulkan-dev vulkan-tools glslc spirv-headers libssl-dev

mkdir -p ~/src
cd ~/src
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp

cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_VULKAN=ON \
  -DGGML_NATIVE=ON

cmake --build build -j"$(nproc)"
```

Check the device:

```bash
./build/bin/llama-bench --version
./build/bin/llama-bench --list-devices
```

Expected family of output:

```text
ggml_vulkan: ... AMD Radeon Graphics (RADV GFX1151) ... uma: 1
```

## 4. Runtime parameters

The measured default recommendation is:

```text
backend       Vulkan / RADV
GPU layers    99
load mode     auto
lazy mode     auto
```

The test build exposed:

```text
-lm,  --load-mode <auto|none|mmap|mlock|mmap+mlock|dio>
-lzm, --lazy-mode <on|auto|off>
```

A no-mmap experiment (`none/off`) did **not** solve the 64 GiB UMA IQ3_M failure. At 96 GiB UMA both loader modes worked and `auto/auto` was marginally cleaner.

## 5. Swap

Recommended ordering from the measured setup:

```text
zram      priority 100
disk swap priority -2
```

Check with:

```bash
swapon --show
```

Do not interpret large swap as successful model offload. More importantly, the clean 512 MiB IQ2_M rerun shows that swap is not the whole story: the system retained ~22 GiB available RAM, used zero swap, allocated ~75 GiB through GTT, and still failed to reach PP/TG after 601 seconds.

## 6. Benchmark method

The core benchmark used:

```text
llama-bench
GPU layers: 99
PP: 512 tokens
TG: 128 tokens
Repetitions: 3
load mode: auto
lazy mode: auto
```

The benchmark harness additionally samples RAM, swap, VRAM, GTT, temperatures and VM paging counters.

`PP512` measures prompt-processing throughput. `TG128` measures token generation. These figures should be treated as **throughput/capacity numbers**, not model-quality rankings.

## 7. Complete UMA comparison

### Generation throughput and capacity

| Model | GGUF | 512 MiB UMA | 64 GiB UMA | 96 GiB UMA |
|---|---:|---:|---:|---:|
| Qwen3 8B Q4_K_M | 4.68 GiB | 41.35 tok/s | 40.96 tok/s | 41.35 tok/s |
| Qwen3-Coder-Next Q4_K_M | 45.09 GiB | **57.84 tok/s** | 57.42 tok/s | 57.53 tok/s |
| Qwen3 235B IQ2_M | 73.16 GiB | **timeout >601 s** | 20.07 tok/s | **20.40 tok/s** |
| Qwen3 235B IQ3_XS | 90.25 GiB | **timeout >302 s** | 17.81 tok/s | **18.07 tok/s** |
| Qwen3 235B IQ3_M | 99.96 GiB | not run | **timeout >600 s** | **17.05 tok/s** |

The 512 MiB profile did **not** provide a significant generation-speed advantage on the models that both 512 MiB and 96 GiB could run. Qwen3 8B was identical at 41.35 tok/s; Coder-Next was 57.84 vs 57.53 tok/s, a difference small enough to treat as run-to-run variation without repeated trials.

### 512 MiB: small/medium success

Qwen3 8B:

```text
PP512:                   1029.64 tok/s
TG128:                     41.35 tok/s
Peak VRAM:                   468 MiB
Peak GTT:                  5,904 MiB
Minimum available RAM:   107,987 MiB
Peak swap:                   54 MiB
Result:                    PASS
```

Qwen3-Coder-Next:

```text
PP512:                    724.62 tok/s
TG128:                     57.84 tok/s
Peak VRAM:                   462 MiB
Peak GTT:                 47,115 MiB
Minimum available RAM:    66,563 MiB
Peak swap:                    0 MiB
Result:                    PASS
```

### 512 MiB: 73.16 GiB cliff

The clean 600-second Qwen3 235B IQ2_M rerun:

```text
Peak VRAM:                   458 MiB
Peak GTT:                 74,985 MiB
Minimum available RAM:    22,308 MiB
Peak swap:                    0 MiB
VM page faults:       29,711,338
Major faults:              1,021
Elapsed:                 601.178 s
Result:                  TIMEOUT before PP/TG
```

This is the most important control against a simple “not enough host RAM” explanation. More than 22 GiB remained available and no swap was used, yet the benchmark never reached inference.

### 512 MiB: 90.25 GiB severe reclaim

Qwen3 235B IQ3_XS:

```text
Peak VRAM:                   504 MiB
Peak GTT:                 92,558 MiB
Minimum available RAM:       267 MiB
Peak swap:               16,270 MiB
Major faults:          1,328,937
Elapsed:                 302.571 s
Result:                  TIMEOUT before PP/TG
```

This run demonstrates the more severe end of the same practical large-GTT boundary.

### 96 GiB control on the exact 73.16 GiB model

Qwen3 235B IQ2_M:

```text
PP512:                    170.09 tok/s
TG128:                     20.40 tok/s
Peak VRAM:                76,128 MiB
Peak GTT:                    351 MiB
Minimum available RAM:    18,420 MiB
Peak swap:                    0 MiB
Major faults:                266
Elapsed:                  91.004 s
Result:                    PASS
```

The exact same 73.16 GiB GGUF that failed to reach inference after 601 seconds at 512 MiB UMA completed the combined PP512 + TG128 benchmark in 91 seconds at 96 GiB UMA.

## 8. The ~100 GiB memory cliff

### 64 GiB UMA, auto/auto

Qwen3 235B IQ3_M never reached PP/TG within 600 s:

```text
Peak VRAM:               65,395 MiB
Peak GTT:                38,645 MiB
Minimum available RAM:    2,678 MiB
Peak swap:                4,025 MiB
Major faults:           193,127
Result:                  TIMEOUT
```

### 64 GiB UMA, none/off

Changing the loader did not fix it:

```text
Peak VRAM:               65,350 MiB
Peak GTT:                38,644 MiB
Minimum available RAM:    1,066 MiB
Peak swap:                3,850 MiB
Major faults:           234,957
Result:                  TIMEOUT
```

### 96 GiB UMA, auto/auto

The same ~100 GiB model completed cleanly:

```text
PP512:                   165.94 tok/s
TG128:                    17.05 tok/s
Peak VRAM:               98,233 MiB
Peak GTT:                 5,697 MiB
Minimum available RAM:   13,264 MiB
Peak swap:                    0 MiB
Major faults:                 0
Result:                  PASS
```

The evidence supports a practical GTT/reclaim/allocation cliff whose location depends strongly on fixed UMA size.

## 9. Recommended profiles

### AI-first: 96 GiB UMA

Use when large local models are the priority.

- Essentially unchanged throughput on tested 5–45 GiB models.
- 73, 90 and ~100 GiB tested models run cleanly.
- ~30 GiB remains conventional host RAM on this machine.
- Best tested overall profile for this user's dedicated local-AI workload.

### Mixed workstation: 64 GiB UMA

Use when you need more host RAM for VMs, containers, browsers or compilation.

- ~62 GiB remains host-visible.
- 73 and 90 GiB tested models pass.
- ~100 GiB IQ3_M does not.

### Host-RAM-first: 512 MiB UMA

Use when conventional host RAM matters more than very large local models.

- ~124 GiB remains host-visible.
- 4.68 and 45.09 GiB tested models perform very well.
- 73.16 GiB failed to reach inference after 601 s despite zero swap.
- 90.25 GiB entered severe reclaim/swap and timed out.
- Do not assume a large Vulkan-reported/GTT address space is equivalent to practical fixed-UMA model capacity.

## 10. Performance-oriented model recommendations

### Best throughput / general work

**Qwen3 30B-A3B Q4_K_M**  
Measured ~85.5 tok/s generation.

### Coding / engineering

**Qwen3-Coder-Next Q4_K_M**  
Measured ~57.5–57.8 tok/s generation at a ~45 GiB GGUF footprint.

### Compact

**Qwen3 8B Q4_K_M**  
Measured ~41.4 tok/s and requires little memory.

### Smaller 235B footprint

**Qwen3 235B IQ2_M**  
Measured ~20.4 tok/s at 96 GiB UMA. The 512 MiB result shows that nominal GTT addressability alone is not sufficient for this ~73 GiB workload on the tested stack.

### Very large model balance

**Qwen3 235B IQ3_XS**  
Measured ~18.1 tok/s at ~90 GiB. At 96 GiB UMA it used only ~369 MiB peak GTT in the measured run.

### Higher-bit 235B option

**Qwen3 235B IQ3_M**  
Measured ~17.1 tok/s at ~100 GiB. Use 96 GiB UMA on this tested system.

### Dense models

The tested dense models were much slower per generated token: Mistral Small 24B ~14.3 tok/s and Llama 3.3 70B ~4.8 tok/s. That is a hardware-efficiency observation, not a quality verdict.

## 11. What not to copy blindly

- Do **not** assume a large Vulkan-reported address space is physical RAM or practical model capacity.
- Do **not** assume 512 MiB UMA + large GTT is universally optimal.
- Do **not** treat BIOS `Auto` as equivalent to a tested fixed reservation.
- Do **not** copy deprecated `amdgpu.gttsize` without understanding your kernel.
- Do **not** add giant disk swap and call it model capacity.
- Do **not** infer model quality from tok/s.
- Do **not** assume full ROCm is necessary; these measurements used Vulkan/RADV.

## 12. Next benchmarks worth adding

- 8K / 32K / 64K context and KV-cache scaling
- TTFT and end-to-end interactive latency
- Flash Attention on/off/auto
- Vulkan vs a current HIP/ROCm build on the same GGUF
- Quality/precision-per-GiB benchmarks comparing IQ2_M / IQ3_XS / IQ3_M
- Power-at-the-wall and sustained thermals
- Repeated trials around the 45–73 GiB 512 MiB UMA boundary to locate the cliff more precisely

## Sources

Benchmark figures: measurements from the test host on 23–27 September 2026, normalized in `data/benchmarks.csv`.

Upstream references:

- https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md
- https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- https://docs.kernel.org/gpu/amdgpu/module-parameters.html
